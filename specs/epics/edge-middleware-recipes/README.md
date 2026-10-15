# Epic: edge-middleware-recipes (EM)

**Vercel's Edge Middleware examples are thirteen Next.js apps that exist for one file each: a `middleware.ts` that reads the visitor's location, a cookie, a header or a flag and rewrites, redirects, answers or decorates. The coverage analysis that drives this programme calls them recipes, not products — so the port is one Cloudflare Worker of recipes, not thirteen Next apps on an adapter. A Hono router mounts each recipe under its own path with the upstream middleware logic kept wherever it is plain web-standard code, the Vercel-only primitive underneath replaced by Cloudflare's, the pages the middleware rewrites to rendered by the Worker, and a test per recipe that proves the upstream behaviour in-process. Around it is the Cirrus baseline's repository shape: an Orun intent, one component per deployable, a credential-free check lane as the merge gate, and an Orun lane that turns on when the product is linked to a workspace.**

What maps to what is the design's first table: `geolocation(req)` is `request.cf`; Edge Config is a var; Upstash over Vercel KV is the Workers Rate Limiting binding; `NextResponse.rewrite` is an in-process dispatch to the recipe's own router; `NextResponse.next/redirect/json` are Hono's `next()`, `c.redirect`, `c.json`; `request.nextUrl` is `new URL(c.req.url)`; `userAgent()` is the same `ua-parser-js` Next bundles. The data the examples ship — the country table, the 50,000 redirects with their generated Bloom filter, the dictionaries, the buckets — is kept as shipped, with its generators.

## Status

| Field | Value |
|-------|-------|
| Status | ✅ Shipped — EM0–EM2 landed (#1, #2, #3) |
| Cluster | **EM** (EM0–EM2) |
| Owner(s) | `apps/recipes` (the Worker) · `tests/recipes` (the in-process request tests) |
| Builds on | `cirrus-baseline` conventions (intent, components, `checks.yml` gate, gated `ci.yml`) and the `cloudflare-worker-turbo` composition its workers deploy with — no bounded context of the fleet is needed |
| Upstream | [vercel/examples `edge-middleware/*`](https://github.com/vercel/examples/tree/main/edge-middleware) at `ecee781` (2026-10-06): geolocation, i18n, basic-auth-password, rate-limit-any-framework, ab-testing-simple, maintenance-page, cookies, add-header, modify-request-header, query-params-filter, json-response, user-agent-based-rendering, redirects-bloom-filter |
| Changes | Ports the thirteen `middleware.ts` (and the libs and data beside them) into one Worker; the Next pages become Hono routes rendering `hono/html`; Vercel-only helpers are replaced per the mapping |
| Decisions locked | (1) One Worker, one repository, one epic — not thirteen Next apps on OpenNext and not thirteen Workers. (2) Hono as the router, one module per recipe on its own base path; `NextResponse.rewrite` is an in-process re-dispatch to that router. (3) The rate limiter is the Workers Rate Limiting binding (GA 2025-09), not a Durable Object: it matches the upstream's 5-per-10-s per-key rule, runs under `wrangler dev`, and the upstream only reads `success`. (4) The maintenance flag is a var per environment; the basic-auth pair is a Worker secret. (5) `wrangler.jsonc` is committed, not rendered — nothing carries a resource id. (6) No infra root. |
| Gate | EM1 is the first user-visible rung (the index and every recipe serve from a Worker). |
| Shipped as | `main` after [#3](https://github.com/sourceplane/edge-middleware-recipes/pull/3); verified locally under `wrangler dev` and the `--env prod` dry run, deploy gated until a workspace is linked |

## Read order

1. `design.md` — the primitive map, the recipe map, the repository, the build, the rejected alternative
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| EM0 — the spec | this doc set and the task contracts | merged on `main` |
| EM1 — the recipes on Workers | `apps/recipes` bundled by wrangler, `tests/recipes`, green checks | `wrangler dev` answers `/` and every recipe as the upstream does; Checks green |
| EM2 — ready to instantiate | README, as-built status | a reader can run, test, preview and deploy it, and knows every departure |
