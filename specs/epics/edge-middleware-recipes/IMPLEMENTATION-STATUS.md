# edge-middleware-recipes (EM) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream examples.

| Milestone | State | PR |
|---|---|---|
| EM0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/edge-middleware-recipes/pull/1) |
| EM1 — the recipes on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/edge-middleware-recipes/pull/2) |
| EM2 — ready to instantiate | ✅ Shipped | [#3](https://github.com/sourceplane/edge-middleware-recipes/pull/3) |

## Departures from the upstream examples

### Across the port

- **One Worker, not thirteen Next apps.** Each `middleware.ts` is a module
  (`apps/recipes/src/recipes/<name>.ts`) exporting a Hono app on its own base
  path; the Next pages (`@vercel/examples-ui`, Tailwind, React) become Hono
  routes rendering `hono/html` templates through one shell. The pages' text is
  the upstream's; their client-side buttons (js-cookie + `router.reload()`)
  are links to routes that set the cookie and redirect.
- **`NextResponse.rewrite` is an in-process dispatch** (`rewrite(app, c, url)`
  in `src/lib/middleware.ts`): `app.fetch(new Request(url, c.req.raw), c.env)`
  against the recipe's own router. A Worker cannot fetch itself. Every rewrite
  targets a path its matcher does not cover.
- **`export const config = { matcher }`** is the path given to `app.use()` /
  `app.on('ALL', [...])`; Hono runs with `strict: false` so `/cookies/` and
  `/cookies` are the same route.
- **The Worker tsconfig** (`tooling/tsconfig/worker.json`: bundler resolution,
  `WebWorker` lib, `@cloudflare/workers-types` 5.x) replaces the upstream Next
  tsconfigs; `strict` + `noUncheckedIndexedAccess` + `noImplicitReturns` cost
  two touches in two upstream libs (below).
- **Brief vs. upstream:** the brief expected `@formatjs/intl-localematcher` +
  `negotiator` for i18n; the upstream at `ecee781` does not use them, so none
  were added (EM-J).

### Per recipe

| Recipe | Departure |
|---|---|
| geolocation | `geolocation(req)` → `request.cf`. The rewrite aims at `/geolocation/index` (Next serves `pages/index.tsx` there too) rather than `/`, so the rewritten request does not re-enter the middleware. An unknown country code (`T1`, `XX`) falls back to the US entry where upstream would throw; a country without a currency renders blank. Latitude, longitude, timezone and colo are passed through the query and shown. `scripts/countries.js` is `scripts/countries.mjs` (the same fetch, written to the new path). |
| i18n | Country from `request.cf`. The flag is `flagcdn.com/96x72/<cc>.png` (as the geolocation page already uses) instead of `public/flags/*.svg`. `lib/api.ts`: `locale: string` and `as Dictionary` for strict TS; the lookup is as written, so `en-US` still falls to the default dictionary, as upstream. |
| basic-auth-password | `'4dmin'` / `'testpwd123'` → `c.env.BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` (Worker secrets; `.dev.vars.example` carries the upstream pair for `wrangler dev`). The protected page no longer prints the credentials. `basicAuth.split(' ')[1] ?? ''` for strict TS. |
| rate-limit-any-framework | `@upstash/ratelimit` + `@vercel/kv` → the Workers Rate Limiting binding (`ratelimits`, 5 per 10 s, `namespace_id` 1001–1004 per environment): per Cloudflare location, approximate, `success` only — `limit`, `reset`, `remaining` are not available (the upstream decided on `success` alone). `ipAddress()` reads `CF-Connecting-IP`. The two HTML pages name Workers instead of Vercel KV. The Durable Object alternative is rejected in the design. |
| ab-testing-simple | `lib/ab-testing.ts`: a return type, `buckets[0] as string`, `[0]!` for strict TS. `ROUTES` keys carry the base path. The `Set-Cookie` is appended to the dispatched response (`serialize` from `hono/cookie`, `Path=/` as Next defaults). Bucket buttons → `/set?page=&bucket=` links. |
| maintenance-page | Edge Config `get('isInMaintenanceMode')` → `c.env.MAINTENANCE_MODE === 'true'`; `GLOBAL_CONFIG` missing → the var missing → `/missing-config` (named for what is missing here) with steps that name `wrangler.jsonc`. The Refresh button is a link. |
| cookies | Opt in / Opt out → `/cookies/opt-in`, `/cookies/opt-out` routes (set the cookie, 302 back). |
| add-header | `NextResponse.next()` → `await next()`; `response.headers.set` → `c.res.headers.set`. |
| modify-request-header | The page is an inner Hono app dispatched a new Request carrying the modified headers (`rewrite(pages, c, url, { headers })`); it also prints `x-from-client` as `(deleted)`. |
| query-params-filter | `NextResponse.redirect(url)` → `c.redirect(url, 307)`. Verbatim otherwise, including `searchParams.forEach` + `delete`, which skips the neighbour of a deleted key and converges over more than one redirect — as upstream. |
| json-response | `NextResponse.json` → `c.json`. |
| user-agent-based-rendering | `userAgent()` from `next/server` → `ua-parser-js` 1.0.41 (MIT; 2.x is AGPL) with `@types/ua-parser-js`. The rewrite path is `/user-agent-based-rendering/_viewport/<viewport>` (upstream writes `_viewport/…` without a leading slash). |
| redirects-bloom-filter | The fetch to `/api/redirects` → an in-process `findRedirect()`; the route is still served. `redirects.json` (5.1 MB) is a dynamic import so esbuild keeps it lazy (`require_redirects()` on the first Bloom hit). The matcher excludes only `/api` (no `_next/*`, `favicon.ico` here). `generate-bloom-filter.ts` moved to `scripts/` with an import attribute and runs under `node --experimental-strip-types` instead of ts-node. `unstable_allowDynamic` is unnecessary: lodash's and reflect-metadata's `Function('return this')` are guarded and never run on workerd. `fromJSON(... as unknown as JSON)` in place of `as any`. |

## Verified

- Local: `pnpm typecheck`, `pnpm lint` (0 warnings), `pnpm test` (14 files,
  25 tests), `pnpm build` (`wrangler deploy --dry-run --outdir dist`,
  6337 KiB / 550 KiB gzipped) green; `wrangler deploy --dry-run --env prod`
  (the Orun verify lane's command) resolves `ENVIRONMENT=prod`,
  `MAINTENANCE_MODE=false` and `RATE_LIMITER (5 requests/10s)`.
- `wrangler dev --port 8804` with `.dev.vars` from the example: `/` lists the
  thirteen; `/geolocation` renders the machine's real `request.cf` (city,
  region code, country, latitude, longitude, timezone, colo) with currency and
  languages; `/i18n` with `Accept-Language: fr` → `Bonjour!` / `locale: fr`,
  `es` → `¡Hola!`, `en-US,en;q=0.9` → the default dictionary;
  `/basic-auth-password` → 401 `WWW-Authenticate: Basic realm="Secure Area"`
  `Auth Required.`, a wrong pair 401, `-u 4dmin:testpwd123` 200;
  `/rate-limit-any-framework` × 7 → `200 200 200 200 200 302 302`, Location
  `/rate-limit-any-framework/blocked.html`; `/ab-testing-simple/home` → 200 +
  `Set-Cookie: bucket-home=c; Path=/` + "bucket C", `-b bucket-marketing=original`
  → the original page with no Set-Cookie, an invalid cookie → a fresh
  assignment; `/maintenance-page/big-promo` → "Something big is coming" with
  the flag off and "Under Maintenance" with `--var MAINTENANCE_MODE:true`
  (port 8805); `/cookies` → "You are not in beta.", `-b beta=true` → "You are
  currently in beta!", `/cookies/opt-in` → 302 + `Set-Cookie: beta=true; Path=/`;
  `/add-header` → `x-modified-edge: true`; `/modify-request-header` with
  `x-from-client: secret` → `hello`, `world!`, `New User Agent overriden by
  middleware!`, `x-from-client: (deleted)`; `/query-params-filter?a=b&allowed=test`
  → 307 `Location: …/query-params-filter?allowed=test`, `?allowed=test` → 200
  `query: ?allowed=test`; `/json-response` → `Content-Type: application/json`
  `{"message":"hello world!"}`; an iPhone User-Agent → "loaded on a mobile
  device", a Mac → desktop; `/redirects-bloom-filter/blog/should-redirect-to-google`
  → 307 `https://www.google.com` (first hit 25 ms, later 20 ms),
  `should-redirect-to-9999` → `?redirect=9999`, `should-render-basic-blog-post`
  → "Blog Post", `/api/redirects?pathname=/blog/should-redirect-to-1` → the
  entry as JSON; `/nope` → 404.
- CI: `Checks` green on #1 and #2 (install, wire, typecheck, lint, test, build).
- Not verified: a live deploy (`ci.yml` is gated until the product is linked
  to an Orun workspace with a Cloudflare connection); the Rate Limiting
  binding against real colos (local is miniflare's simulation); the
  `namespace_id` values against the target account (EM-B); the basic-auth
  secrets set per environment (EM-F).

## Versions

| Package | Version | Why |
|---|---|---|
| hono | ^4.13.0 (4.13.13) | the fleet's router; the factory's Hono lesson |
| wrangler | ^4.151.0 | compatibility_date 2026-10-01; the baseline's pin; `ratelimits` needs ≥ 4.36 |
| @cloudflare/workers-types | ^5.20261006.1 (5.20261015.1) | wrangler 4.151.0's peer range; `RateLimit` and `IncomingRequestCfProperties` are imported as types |
| bloom-filters | ^3.0.1 (3.0.4) | upstream's range; the committed filter JSON is a 3.x `ScalableBloomFilter` export |
| ua-parser-js | ^1.0.40 (1.0.41) | the line Next bundles for `userAgent()`; MIT (2.x is AGPL) |
| @types/ua-parser-js | ^0.7.39 | 1.x ships no types |
| typescript | ^5.8.3 (5.9.3) | the skeleton's floor |
| vitest | ^3.2.4 (3.2.7) | the factory's tests-vitest template |
