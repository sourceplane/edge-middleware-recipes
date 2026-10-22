# edge-middleware-recipes — implementation plan

Milestones land in order; each task is one pull request on an
`orun/EM-n-<slug>` branch with an `Orun-Task: EM-n` trailer.

## EM0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/EM-1.TaskContract.yaml`, `EM-2`, `EM-3` exist (EM-4 joined with EM3)

## EM1 — the recipes on Workers ✅

`apps/recipes` is the thirteen `middleware.ts` as recipe modules behind one
Hono router, with the upstream libs and data beside them, the pages they
rewrite to, and the Worker config around it; `tests/recipes` drives every
recipe in-process with `app.request()`.

**Done when**
- `pnpm install && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally and in `Checks`
- `apps/recipes/dist/index.js` exists after the build (the wrangler dry-run bundle) and the gzipped size is under the paid plan's limit
- `wrangler deploy --dry-run --env prod` (what the Orun verify lane runs) resolves `ENVIRONMENT=prod`, `MAINTENANCE_MODE` and the `RATE_LIMITER` binding
- `wrangler dev` answers `/` with the index and each recipe as the upstream does: geolocation from `request.cf`; `Accept-Language: fr` → the French dictionary; no `Authorization` → 401 + `WWW-Authenticate`, the right pair → 200; the sixth request in 10 s → 302 to `/blocked.html`; `/home` → a bucket page + `Set-Cookie`; `/big-promo` → the promo (flag off), the maintenance page (flag on); `beta=true` → the beta page; `x-modified-edge: true`; the modified request headers printed; `?a=b&allowed=test` → 307 to `?allowed=test`; `{"message":"hello world!"}`; a mobile User-Agent → the mobile page; `/blog/should-redirect-to-google` → 307 to Google, a path not in the table → the blog page

## EM2 — ready to instantiate ✅

The README explains the port, lists the recipes, and says how to run, test,
preview and deploy; `IMPLEMENTATION-STATUS.md` records what shipped and every
departure from the upstream examples.

**Done when**
- the README's quick start works from a fresh clone
- the status file names the PRs and every departure (per recipe)

## EM3 — a baseline (EM-4) ✅

`blueprint.yaml`, `repo-blueprint.yaml` (two phases: `01-product`, the whole
product in one landing; `02-docs`, hook-only), `.baseline/` (identity, task
contracts, the product's README), `tooling/rebrand`, `tooling/bootstrap`,
`hooks/render-deployment-docs.sh`, `ai/context/`, `docs/phases/`,
`BOOTSTRAP.md`, `testing/`, `baseline.yml` and `tag.yml` (design §8); the
product-name seam `apps/recipes/src/site.ts`; the basic-auth recipe's setup
page and its owner-seeded secrets; `checks.yml` on pull requests only and
`ci.yml`'s `linked` gate.

**Done when**
- orun at the bootstrap floor (v2.58.11), at the lane pin (v2.78.4) and at
  v2.79.0 reads `repo-blueprint.yaml`, and `testing/manifest.test.sh` holds
  the card to it
- `Baseline CI` is green: the contract tests, the leak gate, the offline
  bootstrap (`testing/placement.test.sh`) and the end-to-end tier
  (`testing/e2e.test.sh`)
- the status file records what is proven offline and what only a live
  bootstrap can prove

## EM4 — the cirrus standard (EM-5) ✅

Bring the baseline to cirrus-baseline's standard, with nothing about the
recipes themselves changing.

- **No kiox.** `kiox.yaml`/`kiox.lock` pinned an orun (v2.15.0) that nothing
  ran: every workflow installs orun itself through `orun-action` with its own
  `version:`. The files, their two modules and the rebrand's skip entry go.
- **Component docs.** `tooling/catalog/gen-component-docs.py` writes each of
  the two components' `docs/overview.md`, `docs/architecture.md` and
  `docs/runbook.md` from what the component declares, as cirrus-baseline's
  do; the pages ship with the component. Baseline CI runs it with `--check`.
- **The context pack.** `ai/context/current.md`, `decisions.md` and
  `open-risks.md` beside the two pages a product ships with — this
  repository's own, so no module places them.
- **Status that agrees with the tags and the code.** EM3 is shipped and
  tagged; `design.md` and the sequencing note describe `ci.yml`'s gate as
  built (`ws_CHANGE_ME`), not the `ORUN_CI` variable it replaced.
- **The subdomain from the Cloudflare connection (EM-6).** The card's
  `subdomain` input declares `from: connection.cloudflare.workersSubdomain`,
  as cirrus-baseline's does since baseline-v23: the bootstrap door fills it
  from the connection the build is bound to, so the console asks for nothing
  a typo could get wrong. `testing/manifest.test.sh` takes cirrus-baseline's
  rule, which requires the provider in `spec.requires.integrations`.

**Done when**
- nothing outside this milestone's own record names kiox (`git grep -i
  kiox`), and the leak gate and the offline bootstrap pass without the two
  modules
- the docs check is green in Baseline CI
- this file, the status file and `epic.yaml` agree

## EM5 — the domain is set later (EM-7) ✅

**Done when** the console card asks for no domain; `productdomain` is an
optional build input, empty by default; a product built without one is
branded with the reserved placeholder `<reponame>.example.com` where the
domain goes (`BASE_DOMAIN` in `intent.yaml`) and its README says how an
owner sets the real one; Baseline CI places, leak-checks and plans a product
built with no domain. Shipped in `baseline-v3`.

## After EM3 (outside this repository)

1. ✅ Cut `baseline-v1` with `tag.yml` from the merged `main`.
2. Register the row in orun-cloud's `infra/baselines-registry/baselines.yaml`
   (unlisted) with the card vendored at the tag.
3. Bootstrap one product from the tag against a workspace; record its
   timings; then flip the row to public with a page on orunbase.com.

## Sequencing note

EM1 needs nothing but EM0's contracts. EM2 is documentation over EM1's
verified build and can land the same day. EM3 packages EM1's Worker as a
baseline. Deploying to a Cloudflare account
is not a milestone here: it is the Orun lane (`ci.yml`), which plans nothing
while `intent.yaml` names `ws_CHANGE_ME` and turns on once it names the
product's workspace (EM3 replaced the `ORUN_CI` repository variable, which a
bootstrap cannot set). The basic-auth pair is optional: until its owner sets
it (`orun secrets set`, pushed by the next deploy, or `wrangler secret put`),
the recipe answers its setup page (EM-F).
