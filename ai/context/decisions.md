# edge-middleware-recipes — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | One Worker of thirteen recipes, one repository, one epic — not thirteen Next apps on OpenNext, not thirteen Workers | The examples exist for one `middleware.ts` each; they are recipes, not products | `specs/epics/edge-middleware-recipes/design.md` §7, epic README |
| 2 | Hono as the router, one module per recipe on its own base path; `NextResponse.rewrite` is an in-process re-dispatch | The upstream middleware logic stays wherever it is plain web-standard code | design.md §2–§3 |
| 3 | The rate limiter is the Workers Rate Limiting binding, not a Durable Object | It matches the upstream's 5-per-10-s per-key rule, runs under `wrangler dev`, and the upstream only reads `success` | epic README, risk EM-A |
| 4 | The maintenance flag is a var per environment; the basic-auth pair is an optional Worker secret, and without it the recipe answers a 503 setup page | The platform cannot broker the pair; a fresh product must not answer 401 forever | design.md §8, risk EM-F |
| 5 | `wrangler.jsonc` is committed, not rendered; no infra root | Nothing carries a resource id, so nothing is wired and nothing must deploy first | epic README, design.md §8 |
| 6 | One landing (`01-product`) then the record (`02-docs`) | One Worker, no data plane, no domain phase | design.md §8 |
| 7 | The product's name and source link come from one seam (`apps/recipes/src/site.ts`) | The rename rewrites one literal, safely quoted | design.md §8 |
| 8 | The rebrand does not rewrite the rate-limit `namespace_id`s | No input names the account; a derived id could collide just the same | risk EM-B |
| 9 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME` | A bootstrap cannot set a repository variable (replaced the `ORUN_CI` gate) | IMPLEMENTATION-STATUS (EM3) |
| 10 | stack-tectonic 0.19.0, not 0.20.0 | The fleet's site baselines pin it; this Worker's deploy lane is one job, so 0.20.0's shared install saves nothing | design.md §8 |
| 11 | orun is pinned only where it runs (the `orun-action` `version:` in each workflow); no kiox | `kiox.yaml` pinned a version (v2.15.0) nothing ran | IMPLEMENTATION-STATUS (EM4) |
| 12 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph and bindings drifts silently | `tooling/catalog/gen-component-docs.py` |
