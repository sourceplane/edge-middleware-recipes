# 01-product — the product, in one landing

**Places** every module: the root manifests, CI (`ci.yml` — the baseline's
own `baseline.yml` and `tag.yml` are ignored), tooling, the identity file,
the two context pages, `apps/recipes` (the Worker of recipes and its deploy
contract) and `tests/recipes` (vitest). Then
it creates the repository, lands all of it as ONE pull request, and watches
the ONE convergence that merge triggers deploy the Worker to stage and prod.

**Requires** both connections live — GitHub (the App installation on the
account that will OWN the repository, since the platform sees a pull request
only through it) and Cloudflare (every deploy credential is minted from it) —
probed, waited for up to ten minutes each, so a consent can be clicked while
it waits.

## What runs

The run's task set-up — the epic, both milestones, both tasks — runs in the
background from the start (`background: true`), so every hook up to `task`
runs beside it; `task` is the first that waits for it.

| hook | what it does |
|---|---|
| `retouch` | the redeploy marker on `apps/recipes/component.yaml` and `tests/recipes/component.yaml` (`.baseline/tasks/01-product.TaskContract.yaml`'s `affects`) |
| `git-init`, `git-stage` | the tree becomes a repository with a populated index (`rebrand` reads `git ls-files`) |
| `rebrand` | the identity rename: the repo slug, `SITE_NAME` and `SOURCE_URL` in `apps/recipes/src/site.ts`, the Worker name `<reponame>-recipes`, the domain, the workers.dev subdomain, the runtime secrets' refs |
| `orun-workspace` | `intent.yaml`'s `workspace:` → the product's (or `ws_SET_ME`, which fails loudly) |
| `work-tree` | strips the baseline's `work:` block from `intent.yaml` |
| `promotion`, `dev-lanes` | defer prod's wait on stage and dev's push activation until `02-docs` |
| `git-restage`, `rebrand-verify` | the residue sweep over the rewritten tree |
| `repo` | `orun.repo/ensure@v1` — creates `<githuborg>/<reponame>` (pre-created is supported) |
| `link` | links the repository to the workspace, best effort, and stops naming the fix if `orun cloud check` says it is not |
| `secrets` | `orun.integrations/reconcile@v1`, both keys in one hook, created side by side: `CLOUDFLARE_API_TOKEN` from the `workers-deploy` template (Workers Scripts, the Worker's deploy); `CLOUDFLARE_ACCOUNT_ID`, the connection fact; keys that exist are kept |
| `task` | finds the phase's task (opened by the run-level list) and yields its key — waiting, if it must, for the background set-up |
| `land` | one PR bound to the task, its commit checked in the box first (`checks: local`: `orun validate`, then `orun plan` as the PR and as the merge would plan it, under a second); merged without waiting for the PR's CI |
| `converge` (await) | `orun.run/watch@v1` on the merge commit's run (only `ci.yml` runs on a push to main), read every 5 s; resumes it up to three times |
| `verify` (await) | `orun.http/probe@v1` on both workers.dev URLs |

There is no `orun.secrets/exists@v1` in the await: no infra component, so no
`WIRING_*` secret to wait for.

## What the convergence does

`orun plan --changed` on the merge plans `recipes` on stage and prod
(`cloudflare-worker-turbo`, profile `deploy`) and — dev's push activation
being deferred — nothing on dev, so `recipes-tests` (dev only) is not in it.
Stage and prod deploy side by side (the promotion gate is deferred). Each
deploy lane:

1. installs the workspace (`pnpm install --frozen-lockfile`);
2. `verify-worker-structure` — `package.json` and the COMMITTED
   `wrangler.jsonc` exist, checked before any build in the job's staged tree;
3. `wire-fixture` — a no-op: the Worker is not wiring-templated;
4. `build-worker` — `wrangler deploy --dry-run --outdir dist` through turbo;
5. `typecheck-worker`;
6. `wire-live`, `pre-deploy`, `migrate` — no-ops here;
7. `deploy` — `wrangler deploy --env <env>`: `<reponame>-recipes-<env>`;
8. `secrets-live` — pushes `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` if their
   owner has seeded them in Orun; on a fresh product, none are, and it leaves
   the Worker's secrets alone;
9. `smoke` — `/` must list the recipes and `/json-response` must answer
   `{"message":"hello world!"}`, retried with backoff for workers.dev
   propagation.

`recipes-tests` verifies on dev only, on a pull request, and there its lane
installs and checks the package's structure; it does not run the tests. The
landing's own pull request runs `plan` alone, and nothing waits for it — the
same plan ran in the box before the push. The baseline's own CI ran the
typecheck, lint and tests on this exact tree before the tag was cut; in the
product they are `pnpm typecheck`, `pnpm lint` and `pnpm test`, run before a
push.

## Verified

The convergence run for the merge commit is green, and
`https://<reponame>-recipes-{stage,prod}.<subdomain>.workers.dev` answer.

## Troubleshooting

| symptom | cause → fix |
|---|---|
| parks on the `providers` probe | GitHub (on the owner) or Cloudflare is not connected to the workspace. Connect it (console → Integrations), then let the probe see it |
| stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| a secret WRITE fails `not_found` | the API key's role is below admin; re-mint it with the admin role |
| deploy lane: `secret resolution failed … CLOUDFLARE_API_TOKEN` | the reconcile did not run or minted against a revoked connection. Re-connect and re-run the phase; the reconcile re-mints only what is missing |
| deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts Write. Re-issue it with the permission groups the console's Connect recipe lists |
| smoke fails right after the FIRST deploy | workers.dev route propagation; the composition retries the first deploy and the smoke with backoff (stack-tectonic ≥ 0.19.0). A convergence resume clears what is left |
| the watch says green, the probe says 404 | another workflow ran on the push and the watch took its run. Only `ci.yml` may run on a push to main |
| `land`: `the landing's own check failed — orun plan for …` | the placed tree does not plan; the next line is orun's error. Nothing was pushed. Fix it and re-run the phase |
| `/basic-auth-password` answers 503 | expected on a fresh product: its owner has not set `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` (the product README, "Secrets") |
| re-run lands nothing | the hooks did not run (`--run-hooks`), or the contract names no component — `node tooling/bootstrap/retouch.mjs --check --affects .baseline/tasks/01-product.TaskContract.yaml` in the product's tree says which |
