# edge-middleware-recipes — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, secrets inventory) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `02-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the product without any
other source.

## What this system is

Thirteen Edge Middleware recipes — geolocation, i18n, basic auth, rate
limiting, A/B testing, a maintenance page, cookies, response and request
headers, query filtering, a JSON response, user-agent rendering and
Bloom-filter redirects — served by ONE Cloudflare Worker, expressed as an Orun
component-native desired-state repo.

- **`apps/recipes`** — the Worker: a Hono router (`src/index.ts`) mounts each
  recipe under its own path (`src/recipes/<name>.ts`); `/` lists them. The
  product's name and source link are `src/site.ts`. Bundled by wrangler's
  esbuild; no build step beyond it, no static assets, no database.
- **`tests/recipes`** — one vitest file per recipe, driving the Worker
  in-process through `app.request()`; verified on the `dev` rung and by
  `checks.yml` on every pull request.
- **`tooling/*`** — shared TypeScript and ESLint configuration, and the
  deploy-time wrangler renderer for workers that take wiring (this one does
  not: its `wrangler.jsonc` is committed).

The Worker's bindings, all in `apps/recipes/wrangler.jsonc`, repeated per
environment (bindings are not inherited by wrangler environments):

| binding | kind | what reads it |
|---|---|---|
| `ENVIRONMENT` | var | the environment's name |
| `MAINTENANCE_MODE` | var (`"true"`/`"false"`) | the maintenance-page recipe; unset shows its setup dialog |
| `RATE_LIMITER` | Workers Rate Limiting (5 per 10 s, one `namespace_id` per environment) | the rate-limit recipe; created by `wrangler deploy`, nothing to provision |
| `BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD` | Worker secrets, owner-seeded | the basic-auth recipe; unset, it answers a setup page (503) and lets nobody through |

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and check, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. `apps/recipes` deploys once per environment: install, a structure check
   (`package.json` and the committed `wrangler.jsonc`), the wrangler bundle,
   a typecheck, `wrangler deploy --env <env>` of
   `edge-middleware-recipes-recipes-<env>`, the runtime secrets that are
   seeded (below), and a smoke test that fetches `/` and `/json-response`.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/recipes`.
- A rate limiting `namespace_id` is account-wide: two Workers in one account
  that use the same id share counters. Give each product its own ids in
  `wrangler.jsonc` if the account hosts more than one.

## Secrets model

- **Brokered provider secrets**: `CLOUDFLARE_API_TOKEN` (Workers deploy
  scope) and `CLOUDFLARE_ACCOUNT_ID` — pointers minted per run from the
  workspace's Cloudflare connection. No long-lived values at rest; nothing
  to rotate by hand.
- **Owner-seeded runtime secrets**: `BASIC_AUTH_USER` and
  `BASIC_AUTH_PASSWORD`, the basic-auth recipe's pair. No provider holds
  them, so nothing mints them; until both are set the recipe answers its
  setup page. Set them per environment with
  `orun secrets set BASIC_AUTH_USER --env stage` (then `BASIC_AUTH_PASSWORD`,
  then `--env prod`): the component declares them as best-effort references
  (`optionalSecretEnv`), and the next deploy's `secrets-live` step pushes
  every seeded one to the Worker with `wrangler secret bulk`. Trigger that
  deploy by editing the last line of `apps/recipes/component.yaml` (below).
  `wrangler secret put <NAME> --env <env>` in `apps/recipes` works too, and a
  deploy with nothing seeded leaves existing Worker secrets alone.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the Worker on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://edge-middleware-recipes-recipes-stage.your-workers-subdomain.workers.dev/
curl -s https://edge-middleware-recipes-recipes-prod.your-workers-subdomain.workers.dev/json-response

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| change a recipe | edit `apps/recipes/src/recipes/<name>.ts` and its test in `tests/recipes/src/`, merge |
| add a recipe | a module in `apps/recipes/src/recipes/` exporting a Hono app on its own base path and a `meta` entry, registered in `src/recipes/index.ts` |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| redeploy without a change | edit the last line of `apps/recipes/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| turn on basic auth | `orun secrets set BASIC_AUTH_USER --env <env>` and `BASIC_AUTH_PASSWORD`, then redeploy (above) |
| flip maintenance mode | `MAINTENANCE_MODE` in the environment's `vars` in `apps/recipes/wrangler.jsonc`, merge (a flag that must flip without a deploy belongs in a KV namespace) |
| serve a custom domain | attach it to the Worker in Cloudflare (dashboard → Workers & Pages → the Worker → Settings → Domains & Routes); nothing in the code needs it |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase) re-probes the URLs and re-renders
[deployment.md](deployment.md); it is idempotent.

## Evolution

Structural changes (a second Worker, a data store, a KV-backed flag) follow
the same contract that deployed the product: add a component under `apps/`,
`infra/` or `packages/` with a `component.yaml`, land it as a pull request,
and the convergence run applies it.
