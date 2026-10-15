# edge-middleware-recipes

Vercel's [Edge Middleware examples](https://github.com/vercel/examples/tree/main/edge-middleware)
— thirteen small Next.js apps whose whole point is a `middleware.ts` — ported
as **one Cloudflare Worker of recipes**: each `middleware.ts` becomes a module
under `apps/recipes/src/recipes/` with its behaviour intact, mounted by a
[Hono](https://hono.dev) router under its own path, with the demo pages it
rewrites to and a test that proves the upstream behaviour. Around it is the
repository shape of the [Cirrus baseline](https://github.com/sourceplane/cirrus-baseline):
an [Orun](https://github.com/sourceplane/orun) intent, one component per
deployable, a credential-free check lane as the merge gate, and an Orun lane
that turns on once the product is linked to a workspace.

The middleware logic is the upstream's wherever it is plain web-standard code,
comments included. What changes is the Vercel-only primitive underneath —
`geolocation(req)` is `request.cf`, Edge Config is a var, Upstash is the
Workers Rate Limiting binding, `NextResponse.rewrite` is an in-process
dispatch. See [`specs/epics/edge-middleware-recipes`](specs/epics/edge-middleware-recipes/README.md)
for the design (the full primitive map), the milestones and the as-built status.

## The recipes

`/` lists them with `curl` lines to try. Each route is the upstream directory's name.

| Route | What it does | Vercel original |
|---|---|---|
| `/geolocation` | Reads the visitor's country, city and region, adds currency and languages from a country table, rewrites to a page that renders them | [geolocation](https://github.com/vercel/examples/tree/main/edge-middleware/geolocation) — `geolocation(req)` → `request.cf` |
| `/i18n` | Locale from `Accept-Language`, country from the visitor's location; rewrites `/` to `/<locale>/<country>` and renders that locale's dictionary | [i18n](https://github.com/vercel/examples/tree/main/edge-middleware/i18n) |
| `/basic-auth-password` | Checks `Authorization: Basic`; anything else is rewritten to a 401 with `WWW-Authenticate` | [basic-auth-password](https://github.com/vercel/examples/tree/main/edge-middleware/basic-auth-password) — hard-coded pair → Worker secrets |
| `/rate-limit-any-framework` | 5 requests per 10 s per IP; the sixth is redirected to `/blocked.html` | [rate-limit-any-framework](https://github.com/vercel/examples/tree/main/edge-middleware/rate-limit-any-framework) — Upstash → the `ratelimits` binding |
| `/ab-testing-simple` | Assigns `/home` and `/marketing` visitors a bucket in a cookie and rewrites to that bucket's page | [ab-testing-simple](https://github.com/vercel/examples/tree/main/edge-middleware/ab-testing-simple) |
| `/maintenance-page` | Serves the maintenance page for `/big-promo` while a flag is on, a setup dialog when it is missing | [maintenance-page](https://github.com/vercel/examples/tree/main/edge-middleware/maintenance-page) — Edge Config → `MAINTENANCE_MODE` var |
| `/cookies` | Rewrites `/` to the beta or non-beta page from the `beta` cookie | [cookies](https://github.com/vercel/examples/tree/main/edge-middleware/cookies) |
| `/add-header` | Adds `x-modified-edge: true` to every response | [add-header](https://github.com/vercel/examples/tree/main/edge-middleware/add-header) |
| `/modify-request-header` | Adds, overrides and deletes request headers before the route runs; the page prints what it received | [modify-request-header](https://github.com/vercel/examples/tree/main/edge-middleware/modify-request-header) |
| `/query-params-filter` | Strips every query parameter but `allowed` and redirects (307) to the clean URL | [query-params-filter](https://github.com/vercel/examples/tree/main/edge-middleware/query-params-filter) |
| `/json-response` | Answers from the middleware with `{"message":"hello world!"}` | [json-response](https://github.com/vercel/examples/tree/main/edge-middleware/json-response) |
| `/user-agent-based-rendering` | Rewrites `/` to the mobile or desktop page from the User-Agent | [user-agent-based-rendering](https://github.com/vercel/examples/tree/main/edge-middleware/user-agent-based-rendering) — `userAgent()` → ua-parser-js |
| `/redirects-bloom-filter` | Checks every path against a Bloom filter of 50,000 redirects and redirects on a hit (307/308) | [redirects-bloom-filter](https://github.com/vercel/examples/tree/main/edge-middleware/redirects-bloom-filter) — Route Handler fetch → in-process lookup |

## What is here

| Surface | Where |
|---|---|
| The Worker — `/` index, one module per recipe | `apps/recipes/src/index.ts`, `apps/recipes/src/recipes/<name>.ts` |
| The Edge Middleware verbs on a Worker (`rewrite`, `geolocation`, `ipAddress`, `userAgent`) | `apps/recipes/src/lib/middleware.ts` |
| Upstream data kept as shipped (country table, 50,000 redirects + generated Bloom filter, dictionaries, buckets) | `apps/recipes/src/recipes/<name>/` |
| The generators (country table, Bloom filter) | `apps/recipes/scripts/` |
| Worker config (name, compatibility, per-environment vars, the rate limiting binding) | `apps/recipes/wrangler.jsonc` |
| Secrets for `wrangler dev` | `apps/recipes/.dev.vars.example` → `.dev.vars` |
| Deploy contract | `apps/recipes/component.yaml` (`cloudflare-worker-turbo`) |
| Tests — one per recipe, in-process through `app.request()` | `tests/recipes/src/*.test.ts` |

## Getting started

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test             # 25 tests: every recipe's upstream behaviour, in-process (no workerd)
pnpm build            # wrangler deploy --dry-run → apps/recipes/dist (the bundle, no upload)
```

Run the Worker locally under workerd and try the recipes:

```bash
cp apps/recipes/.dev.vars.example apps/recipes/.dev.vars   # the basic-auth pair
pnpm --filter @app/recipes dev                             # http://localhost:8787

curl -s http://localhost:8787/                             # the index, with a curl line per recipe
curl -s -H 'Accept-Language: fr' http://localhost:8787/i18n | grep Bonjour
curl -si -u 4dmin:testpwd123 http://localhost:8787/basic-auth-password | head -1
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%{http_code} ' http://localhost:8787/rate-limit-any-framework; done
curl -si 'http://localhost:8787/query-params-filter?a=b&allowed=test' | grep -i location
curl -si http://localhost:8787/redirects-bloom-filter/blog/should-redirect-to-google | grep -i location
```

`request.cf` (geolocation, i18n) is real under `wrangler dev` — wrangler fetches
the machine's own. To see the maintenance page: `pnpm --filter @app/recipes dev -- --var MAINTENANCE_MODE:true`.

Add a recipe: a module in `apps/recipes/src/recipes/` that exports a Hono app
on its own base path and a `meta` entry, registered in `src/recipes/index.ts`;
its `app.use(<matcher>, …)` is the upstream's `export const config = { matcher }`.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Thirteen Next.js apps, each run by Vercel's framework builder with its `middleware.ts` at the edge | One Cloudflare Worker: Hono routes each recipe under `/<name>`; `export default app` is the module handler |
| `geolocation(req)` (`@vercel/functions`), `ipAddress(req)` (`@vercel/edge`), `userAgent(req)` (`next/server`) | `request.cf`, `CF-Connecting-IP`, `ua-parser-js` — `apps/recipes/src/lib/middleware.ts` |
| `NextResponse.next()` · `.rewrite(url)` · `.redirect(url)` · `.json(body)` | `await next()` · `rewrite(app, c, url)` (in-process dispatch) · `c.redirect(url, 307)` · `c.json(body)` |
| Edge Config (`isInMaintenanceMode`) | The `MAINTENANCE_MODE` var per environment (a flag that must flip without a deploy: Workers KV) |
| `@upstash/ratelimit` over Vercel KV | The Workers Rate Limiting binding (`ratelimits` in `wrangler.jsonc`) |
| `vc dev` · `vc build` · `vc deploy` | `wrangler dev` · `wrangler deploy --dry-run --outdir dist` · `wrangler deploy --env <stage\|prod>` |
| Deploy on push | Orun deploys `edge-middleware-recipes-recipes-{stage,prod}` on merge to `main` (`apps/recipes/component.yaml`) |

## Deploying

`.github/workflows/checks.yml` runs install, typecheck, lint, test and build on
every push and pull request. `ci.yml` is the Orun deployment pipeline: set
`execution.state.workspace` in `intent.yaml` to this product's Orun workspace
(`orun cloud link`), connect a Cloudflare account to that workspace, and set
the `ORUN_CI` repository variable to `true`. From then on a merge to `main`
deploys the Worker to `stage`, then `prod`.

Before the first deploy, set the basic-auth pair for each environment — the
deploy lane does not create secrets:

```bash
cd apps/recipes
pnpm exec wrangler secret put BASIC_AUTH_USER --env stage
pnpm exec wrangler secret put BASIC_AUTH_PASSWORD --env stage   # and --env prod
```

The rate limiting binding needs no resource: wrangler creates the namespace
from `wrangler.jsonc` on deploy (one `namespace_id` per environment).
