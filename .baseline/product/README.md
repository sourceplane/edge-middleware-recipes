# edge-middleware-recipes

Thirteen Edge Middleware recipes on **one Cloudflare Worker**: each recipe is
a module mounted by a [Hono](https://hono.dev) router under its own path,
with the demo pages it rewrites to and a test that proves its behaviour. They
are Vercel's [Edge Middleware examples](https://github.com/vercel/examples/tree/main/edge-middleware)
(MIT), each `middleware.ts` kept wherever it is plain web-standard code, the
Vercel-only primitive underneath swapped for Cloudflare's.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets inventory into
[ai/context/deployment.md](ai/context/deployment.md); how the product
deploys and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## The recipes

`/` lists them with `curl` lines to try. Each route is the upstream example's
name.

| Route | What it does | On Cloudflare |
|---|---|---|
| `/geolocation` | Reads the visitor's country, city and region, adds currency and languages from a country table, rewrites to a page that renders them | `request.cf` |
| `/i18n` | Locale from `Accept-Language`, country from the visitor's location; rewrites `/` to `/<locale>/<country>` and renders that locale's dictionary | `request.cf` |
| `/basic-auth-password` | Checks `Authorization: Basic`; anything else is rewritten to a 401 with `WWW-Authenticate` | Worker secrets `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` — see [Secrets](#secrets) |
| `/rate-limit-any-framework` | 5 requests per 10 s per IP; the sixth is redirected to `/blocked.html` | the Workers Rate Limiting binding |
| `/ab-testing-simple` | Assigns `/home` and `/marketing` visitors a bucket in a cookie and rewrites to that bucket's page | cookies |
| `/maintenance-page` | Serves the maintenance page for `/big-promo` while a flag is on, a setup dialog when it is missing | the `MAINTENANCE_MODE` var |
| `/cookies` | Rewrites `/` to the beta or non-beta page from the `beta` cookie | cookies |
| `/add-header` | Adds `x-modified-edge: true` to every response | — |
| `/modify-request-header` | Adds, overrides and deletes request headers before the route runs; the page prints what it received | — |
| `/query-params-filter` | Strips every query parameter but `allowed` and redirects (307) to the clean URL | — |
| `/json-response` | Answers from the middleware with `{"message":"hello world!"}` | — |
| `/user-agent-based-rendering` | Rewrites `/` to the mobile or desktop page from the User-Agent | `ua-parser-js` |
| `/redirects-bloom-filter` | Checks every path against a Bloom filter of 50,000 redirects and redirects on a hit (307/308) | an in-process lookup |

## What is here

| Surface | Where |
|---|---|
| The product's name and source link | `apps/recipes/src/site.ts` |
| The Worker — `/` index, one module per recipe | `apps/recipes/src/index.ts`, `apps/recipes/src/recipes/<name>.ts` |
| The Edge Middleware verbs on a Worker (`rewrite`, `geolocation`, `ipAddress`, `userAgent`) | `apps/recipes/src/lib/middleware.ts` |
| Recipe data (country table, 50,000 redirects + their Bloom filter, dictionaries, buckets) and its generators | `apps/recipes/src/recipes/<name>/`, `apps/recipes/scripts/` |
| Worker config (name, compatibility, per-environment vars, the rate limiting binding) | `apps/recipes/wrangler.jsonc` |
| Secrets for `wrangler dev` | `apps/recipes/.dev.vars.example` → `.dev.vars` |
| Deploy contract | `apps/recipes/component.yaml` |
| Tests — one per recipe, in-process through `app.request()` | `tests/recipes/src/*.test.ts` |

## Getting started

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test             # every recipe's behaviour, in-process (no workerd)
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

`request.cf` (geolocation, i18n) is real under `wrangler dev` — wrangler
fetches the machine's own. To see the maintenance page:
`pnpm --filter @app/recipes dev -- --var MAINTENANCE_MODE:true`.

Make it yours in `apps/recipes/src/site.ts` (the name on the index page and
in every footer, and the repository the footer links to). Add a recipe: a
module in `apps/recipes/src/recipes/` that exports a Hono app on its own base
path and a `meta` entry, registered in `src/recipes/index.ts`; its
`app.use(<matcher>, …)` is the upstream's `export const config = { matcher }`.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. The Worker deploys to `stage`, then
to `prod` once stage has converged on the same commit; `dev` only verifies.
It is `edge-middleware-recipes-recipes-<env>` on your account's workers.dev
subdomain, and every deploy is smoke-tested over HTTP. `checks.yml` runs
install, typecheck, lint, test and build on every pull request. (A push to
`main` runs `ci.yml` alone, which builds, typechecks and deploys.)

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id are brokered per run from the workspace's
Cloudflare connection; nothing provider-shaped is stored in the repository
or in GitHub. The rate limiting binding needs no resource: `wrangler deploy`
creates its namespace from `wrangler.jsonc` (one `namespace_id` per
environment — account-wide, so give another product in the same account its
own ids).

## Secrets

Every recipe but one works on a fresh deploy with no secret at all. The
basic-auth recipe checks a user and password that are yours to choose, so
until both are set it answers a setup page (503) that says how, and lets
nobody through. Set them per environment:

```bash
orun secrets set BASIC_AUTH_USER --env stage        # prompts for the value
orun secrets set BASIC_AUTH_PASSWORD --env stage    # and the same for --env prod
```

then redeploy: edit the last line of `apps/recipes/component.yaml` (the
`# orun: redeploy …` marker; nothing reads it) and merge. The deploy pushes
every seeded secret to the Worker after it uploads it. Or set them on the
Worker directly — the deploy leaves Worker secrets alone when none are
seeded in Orun:

```bash
cd apps/recipes
pnpm exec wrangler secret put BASIC_AUTH_USER --env stage
pnpm exec wrangler secret put BASIC_AUTH_PASSWORD --env stage   # and --env prod
```

## Custom domain

The Worker answers on workers.dev from its first deploy. To serve it on your
own domain, add the domain to the Cloudflare account it deploys into and
attach it to the Worker (dashboard → Workers & Pages →
`edge-middleware-recipes-recipes-prod` → Settings → Domains & Routes → Add →
Custom domain); do the same for stage with a subdomain if you want one. No
recipe builds absolute links to itself, so nothing else changes.
