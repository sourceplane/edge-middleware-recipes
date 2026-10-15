# edge-middleware-recipes — implementation plan

Milestones land in order; each task is one pull request on an
`orun/EM-n-<slug>` branch with an `Orun-Task: EM-n` trailer.

## EM0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/EM-1.TaskContract.yaml`, `EM-2`, `EM-3` exist

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

## Sequencing note

EM1 needs nothing but EM0's contracts. EM2 is documentation over EM1's
verified build and can land the same day. Deploying to a Cloudflare account
is not a milestone here: it is the Orun lane (`ci.yml`) that turns on when
`intent.yaml`'s workspace is set and the `ORUN_CI` variable is `true`; the
basic-auth secrets are set per environment with `wrangler secret put` before
the first deploy.
