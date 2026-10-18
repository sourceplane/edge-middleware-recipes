# edge-middleware-recipes — design

## 1. What the templates are

Thirteen directories under `vercel/examples/edge-middleware`. Twelve are a
Next.js app (pages router, `@vercel/examples-ui`, Tailwind) whose
`middleware.ts` is the example; the pages exist to show what the middleware
did. One (`rate-limit-any-framework`) is two static HTML files behind a
`middleware.js` that uses `@vercel/edge`. Each middleware is a few lines on
top of a Vercel-only primitive: `geolocation(req)` from `@vercel/functions`,
`get()` from `@vercel/global-config` (Edge Config), `@upstash/ratelimit` over
`@vercel/kv`, `ipAddress(req)` from `@vercel/edge`, `userAgent(req)` from
`next/server`, and `NextResponse.{next,rewrite,redirect,json}` with
`request.nextUrl`. The data some ship — a 250-country table, 50,000 redirects
with a generated Bloom filter, dictionaries, bucket lists — is plain JSON and
TypeScript beside the middleware.

## 2. The primitive map (Vercel → Cloudflare)

Every Vercel primitive the thirteen middlewares use, and what stands in for it
in `apps/recipes/src/lib/middleware.ts` or Hono.

| Vercel primitive | Used by | Here |
|---|---|---|
| `geolocation(req)` (`@vercel/functions`; the `x-vercel-ip-*` headers) | geolocation, i18n | `geolocation(c.req.raw)`: `request.cf` — `country`, `city`, `regionCode` (= `countryRegion`), `latitude`, `longitude`, `timezone`, `colo` (= `region`); the flag emoji is derived as Vercel does |
| Edge Config — `get('isInMaintenanceMode')` behind the `GLOBAL_CONFIG` connection string | maintenance-page | The `MAINTENANCE_MODE` var per environment in `wrangler.jsonc`; unset reproduces the upstream's "missing config" dialog. A flag that has to flip without a deploy belongs in a KV namespace read with `env.KV.get()` — the factory's `cloudflare-kv` root and a wiring template provide it; not done here, the recipe shows the read |
| `@upstash/ratelimit` `Ratelimit.slidingWindow(5, '10 s')` over `@vercel/kv` | rate-limit-any-framework | The Workers Rate Limiting binding: `ratelimits: [{ name: "RATE_LIMITER", simple: { limit: 5, period: 10 } }]`, `env.RATE_LIMITER.limit({ key })` → `{ success }`. GA since 2025-09-19, simulated by `wrangler dev`, no network round trip, per Cloudflare location and approximate by design; it returns only `success` (the upstream destructures `limit`, `reset`, `remaining` too but decides on `success` alone). One `namespace_id` per environment so stage and prod do not share counters |
| `ipAddress(req)` (`@vercel/edge`) | rate-limit-any-framework | `ipAddress(c.req.raw)`: the `CF-Connecting-IP` header |
| `userAgent(req)` (`next/server`) | user-agent-based-rendering | `userAgent(c.req.raw)`: `ua-parser-js` 1.x — the package Next bundles for the same helper — `.getResult()` |
| `NextResponse.next()` then `response.headers.set(...)` | add-header | `await next()` then `c.res.headers.set(...)` |
| `NextResponse.next({ request: { headers } })` | modify-request-header | `rewrite(pages, c, c.req.url, { headers })`: the recipe's routes are dispatched a new Request carrying the headers (a Worker's incoming Request is immutable) |
| `NextResponse.rewrite(url)` | geolocation, i18n, basic-auth-password, ab-testing-simple, maintenance-page, cookies, user-agent-based-rendering | `rewrite(app, c, url)`: a Worker cannot fetch itself, so the rewrite is an in-process dispatch — `app.fetch(new Request(url, c.req.raw), c.env)` against the recipe's own router; the browser keeps its URL |
| `NextResponse.redirect(url[, status])` (307 by default) | query-params-filter, redirects-bloom-filter | `c.redirect(url, 307 \| 308)`; `Response.redirect(url)` (302) where upstream used it |
| `NextResponse.json(body)` | json-response | `c.json(body)` |
| `request.nextUrl` (a mutable `URL`) | most | `new URL(c.req.url)` |
| `req.cookies.get(name)?.value` · `res.cookies.set(name, value)` | cookies, ab-testing-simple | `getCookie(c, name)` · `setCookie(c, …)` / `serialize(name, value, { path: '/' })` from `hono/cookie` |
| `export const config = { matcher }` | all | The path given to `app.use(path, …)` or `app.on('ALL', [paths], …)` on the recipe's router — `'/'` is `app.use('/')`, `['/', '/index']` is `app.on('ALL', ['/', '/index'])`, `'*'` is `app.use('*')` |
| `process.env.X` | basic-auth-password (implied), maintenance-page | `c.env.X` — a var (`wrangler.jsonc`) or a secret (`wrangler secret put`, `.dev.vars` locally) |
| `fetch()` to the app's own Route Handler (`/api/redirects`) | redirects-bloom-filter | An in-process function the middleware calls (a Worker cannot fetch itself); the route is still served at `/api/redirects` |
| Next pages (`pages/*.tsx`, `@vercel/examples-ui`, Tailwind) | all | Hono routes rendering `hono/html` templates through one shell (`src/lib/page.ts`); client-side buttons (js-cookie + reload) become links to routes that set the cookie and redirect |
| `vc dev` · `vc build` · `vc deploy` | — | `wrangler dev` · `wrangler deploy --dry-run --outdir dist` · Orun's `cloudflare-worker-turbo` with `--env stage` / `--env prod` |

## 3. The recipe map

One row per recipe: its route, what was kept verbatim, what the port changed.

| Recipe | Route | Kept verbatim | Changed |
|---|---|---|---|
| geolocation | `/geolocation` (page at `/geolocation/index`) | The middleware body and comments; `lib/countries.json` (250 entries) and `scripts/countries.js` as `scripts/countries.mjs` | `geolocation(req)` → `request.cf`; the rewrite aims at `/index` (Next serves `pages/index.tsx` there too) so the rewritten request does not re-enter the `/` middleware; an unknown country code falls back to the US entry instead of throwing; countries without a currency render blank; latitude, longitude, timezone and colo are passed and shown |
| i18n | `/i18n` → `/i18n/<locale>/<country>` | The middleware; `lib/{constants,types,api}.ts` (api.ts: `locale: string` and one cast for strict TS) | Country from `request.cf`; the flag from flagcdn.com instead of `public/flags/*.svg` (a plain Worker ships no static assets) |
| basic-auth-password | `/basic-auth-password` (and `/index`), 401 at `/api/auth` | The header parsing, the rewrite, the 401 with `WWW-authenticate: Basic realm="Secure Area"` and body `Auth Required.` | `'4dmin'` / `'testpwd123'` → the `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` secrets (`.dev.vars.example` carries the upstream pair); the protected page no longer prints them |
| rate-limit-any-framework | `/rate-limit-any-framework`, `/blocked.html` | The decision (`success ? next() : Response.redirect(new URL('/blocked.html', …))`), the two pages' structure | Upstash + KV → the Rate Limiting binding; `ipAddress` → `CF-Connecting-IP`; the pages name Workers instead of Vercel KV |
| ab-testing-simple | `/ab-testing-simple/home`, `/marketing` → `/<page>/<bucket>` | The middleware; `lib/ab-testing.ts` (two strict-TS touches), `lib/buckets.ts` | `ROUTES` keys carry the base path; the Set-Cookie is appended to the dispatched response; the bucket buttons are links to `/set?page=&bucket=` |
| maintenance-page | `/maintenance-page/big-promo` → `/maintenance` or `/missing-config` | The middleware's three-way shape and comments; the three pages' text | Edge Config `get()` → `c.env.MAINTENANCE_MODE === 'true'`; `GLOBAL_CONFIG` missing → the var missing; the dialog's steps name `wrangler.jsonc` |
| cookies | `/cookies` → `/beta` or `/non-beta` | The middleware (`JSON.parse(cookie \|\| 'false')`, the rewrite) | Opt in / out are `/opt-in`, `/opt-out` routes that set the cookie and redirect |
| add-header | `/add-header` | The middleware's three steps and comments | `NextResponse.next()` → `await next()`; `response.headers` → `c.res.headers` |
| modify-request-header | `/modify-request-header` | The `Headers` cloning, the two adds, the override, the delete, with comments | The page is dispatched a new Request with the headers (`rewrite(pages, …, { headers })`); it also prints the deleted header as `(deleted)` |
| query-params-filter | `/query-params-filter` | The whole middleware, including `searchParams.forEach` + `delete` (which skips a neighbour and converges over more than one redirect, as upstream) | `NextResponse.redirect(url)` → `c.redirect(url, 307)` |
| json-response | `/json-response` | The middleware | `NextResponse.json` → `c.json` |
| user-agent-based-rendering | `/user-agent-based-rendering` → `/_viewport/{mobile,desktop}` | The middleware and comments; the Home page's text | `userAgent()` → `ua-parser-js`; the rewrite path carries the base and a leading slash |
| redirects-bloom-filter | `/redirects-bloom-filter/*`, lookup at `/api/redirects`, pages at `/` and `/blog/:slug` | The middleware's flow and comments; `redirects/{redirects.json, redirects-bloom-filter.json, types.ts}`; the generator as `scripts/generate-bloom-filter.ts`; the Route Handler's code | The Route Handler fetch → an in-process call; the 5 MB table is a dynamic import esbuild keeps lazy (parsed on the first Bloom hit, not at isolate start); the matcher excludes only `/api`; `unstable_allowDynamic` is unnecessary — lodash's and reflect-metadata's `Function('return this')` are guarded and never run on workerd |

## 4. The repository

```
apps/recipes                 the Worker: src/index.ts (the index page, mounts every recipe)
  src/recipes/<name>.ts      one module per upstream example: a Hono app on its own base path + meta
  src/recipes/<name>/        the upstream's lib/ and data, as shipped
  src/lib/middleware.ts      the Edge Middleware verbs on a Worker (rewrite, geolocation, ipAddress, userAgent)
  src/lib/page.ts            the one HTML shell the demo pages share
  scripts/                   countries.mjs, generate-bloom-filter.ts (the upstream generators)
  wrangler.jsonc             name, compatibility date, nodejs_compat, observability, vars + ratelimits per env
  .dev.vars.example          BASIC_AUTH_USER / BASIC_AUTH_PASSWORD for wrangler dev
  component.yaml             Orun component: build with turbo, dry-run/deploy with wrangler --env
tests/recipes                vitest: one file per recipe, app.request() in-process (a fake rate limiter, a cf object on the Request)
tooling/*                    shared tsconfig / eslint / wrangler wiring renderer (unused here: nothing to wire)
intent.yaml                  environments dev (verify) · stage · prod; `work:` points at specs/epics and tasks
.github/workflows            checks.yml (merge gate) · ci.yml (Orun lanes; plans nothing while intent.yaml names ws_CHANGE_ME)
```

## 5. The build

`pnpm --filter @app/recipes build` = `wrangler deploy --dry-run --outdir dist`:
esbuild bundles `src/index.ts`, Hono, `bloom-filters`, `ua-parser-js` and the
JSON data into `dist/index.js` — 6.3 MiB, 550 KiB gzipped (the limit that
applies is the compressed one: 3 MiB free, 10 MiB paid). The redirect table is
in a lazy `require_redirects()` wrapper. Orun's verify profile runs the same
dry run with `--env prod`; the deploy profile drops `--dry-run`. There is no
framework build step.

## 6. Out of scope

A KV-backed flag for the maintenance page (the recipe shows the read; the
`cloudflare-kv` root + wiring template is the factory's shape for it), a
Durable Object limiter (exact and global, at a round trip per request — the
upstream rule does not need it), custom domains (an owner's step after the
bootstrap; §8), Next's `_next/*` and
`favicon.ico` matcher exclusions (there are none here), and the upstream pages'
styling (`@vercel/examples-ui`, Tailwind, React).

## 7. The rejected alternative

**Thirteen Next.js apps on `@opennextjs/cloudflare`.** Each example would be an
`apps/<name>` with its own OpenNext build, Worker + static assets, wrangler
config and component — thirteen deploys for thirteen files of middleware — and
the middleware would run as OpenNext's "Node.js middleware" inside the adapter,
which hides exactly the thing the examples teach: what the edge primitive is
and what it costs. The Vercel-only helpers would still have to be replaced one
by one. The coverage analysis calls these recipes; a recipe is a module you
read and copy, not a product you deploy. Also rejected: one Worker per recipe
(thirteen env sections and components for the same reason), and a Durable
Object rate limiter (correct, but a migration and a round trip the native
binding makes unnecessary for a 5-per-10-s rule that only reads `success`).

## 8. The baseline (EM3)

The repository instantiates new products the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) does at
`baseline-v22`: a console card (`blueprint.yaml`) the platform renders, a
build document (`repo-blueprint.yaml`) `orun new` runs, and a rename engine
that makes the copy somebody else's. What a small baseline carries — the
`.baseline/` identity and contracts, the product README, the bootstrap
helpers, the deployment-record hook, `ai/context`, the `testing/` suite, the
`baseline.yml`/`tag.yml` lanes and `ci.yml`'s `linked` gate — is
portfolio-starter-kit's (`baseline-v2`); HOW the build runs is cirrus v22's:
the whole product in ONE landing.

| Cirrus v22 | Here | Why the difference |
|---|---|---|
| `01-product` (everything, one PR, one convergence), `07-domain` (optional), `08-docs` | `01-product`, `02-docs` | one Worker, no data plane, no domain phase |
| `dependsOn: cloudflare-d1` (enforced on main) so the data plane deploys first; an `orun.secrets/exists@v1` await on `WIRING_*` | neither | no infra: the Worker's bindings are vars, a rate limiting binding `wrangler deploy` creates, and owner-seeded secrets — nothing carries a resource id, so nothing is wired and nothing must deploy first |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_D1_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `CLOUDFLARE_API_TOKEN` (`workers-deploy`), `CLOUDFLARE_ACCOUNT_ID` (`account-id`) | the deploy profile's `secretBindings` are the only refs; no D1 |
| POLAR_* as `optionalSecretEnv` + `runtimeSecrets` | `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` the same way | the pair is the owner's, not a provider's: the card cannot broker it, so it never asks; seeded later, `secrets-live` pushes it on the next deploy |
| task contracts in `tasks/` | `.baseline/tasks/` | `tasks/` is this repository's own work tree (`intent.yaml` `work:`), where an unkeyed contract is an error |
| ships its own README | ships `.baseline/product/README.md` | this README is about the baseline |
| — | `work-tree.mjs` strips `work:` from the product's intent | a product has no `specs/` or `tasks/` |
| stack-tectonic 0.20.0 | 0.19.0 | the fleet's site baselines pin it (Next 16's Turbopack cannot build through 0.20.0's lane-linked `node_modules`); this Worker would build either way, and its deploy lane is one job, so the shared install saves nothing |
| rebrand rules for a SaaS | the source link, the `SITE_NAME` seam (`apps/recipes/src/site.ts`), the domain, the subdomain, the Worker name `<slug>-recipes`, the secret refs, the repo slug | the identity this tree carries |

**The product-name seam** is `apps/recipes/src/site.ts`: `SITE_NAME` is the
index page's `<title>` and heading and every page's footer; `SOURCE_URL` is
the footer's source link. The rename writes the name with `JSON.stringify`,
so any name the card admits — apostrophes and ampersands included — stays a
valid string, and `hono/html` escapes it on the page.

**No secret the platform cannot broker.** The basic-auth recipe's pair was
a Worker secret the deploy lane never sets, so a fresh product would have
answered 401 to everyone, forever, with nothing saying why. Without the pair
the recipe now rewrites to a setup page (503, after maintenance-page's
missing-config dialog) that says how to set it — `orun secrets set …` and the
next deploy, or `wrangler secret put` — and never serves the protected page.
With it, the upstream behaviour is unchanged.

**The e2e runs the lane as the plan renders it.** The PR-trigger plan carries
every non-mutating step of the stage lane (the deploy profile has no
`deploy-dry-run`): install, `verify-worker-structure` (package.json and the
committed `wrangler.jsonc`, BEFORE the build), `wire-fixture` (a no-op: not
templated), `build-worker`, `typecheck-worker`, `deploy-dry-run`.
`testing/e2e.test.sh` runs exactly those, in the job tree orun stages from a
pristine checkout, then serves the Worker with `wrangler dev --env stage` and
reads every recipe — and the Rate Limiting binding, which only workerd
answers.
