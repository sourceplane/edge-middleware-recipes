# edge-middleware-recipes (EM) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream examples.

| Milestone | State | PR |
|---|---|---|
| EM0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/edge-middleware-recipes/pull/1) |
| EM1 — the recipes on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/edge-middleware-recipes/pull/2) |
| EM2 — ready to instantiate | ✅ Shipped | [#3](https://github.com/sourceplane/edge-middleware-recipes/pull/3) |
| EM3 — a baseline | ✅ Shipped | [#4](https://github.com/sourceplane/edge-middleware-recipes/pull/4) (EM-4), tagged `baseline-v1` |
| EM4 — the cirrus standard | ✅ Shipped | EM-5 — on `main` after `baseline-v1`, not yet tagged |

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

## Departures from the port (EM3)

| What | Before | After | Why |
|---|---|---|---|
| The product's name | "Edge Middleware recipes" written into the index's `<title>` and heading; footer "← all recipes" | `SITE_NAME` / `SOURCE_URL` in `apps/recipes/src/site.ts`; the index's title and heading, every footer's home link and a `source` link | the seam the baseline's rename rewrites (design §8) |
| basic-auth-password without its secrets | 401 to everyone, forever | rewrites to `/basic-auth-password/missing-config`: a 503 setup page naming `orun secrets set` and `wrangler secret put`; the protected page is never served | a fresh product has no pair and the platform cannot broker one (risks EM-F) |
| `apps/recipes/component.yaml` | `smokeCommand` an `echo`; `orgName`/`owner`/`repo`, `dryRunCommand`/`deployCommand` (both `--env prod`) | a real smoke (`/` lists the recipes, `/json-response` answers); `optionalSecretEnv` + `runtimeSecrets` for the basic-auth pair; the unused parameters dropped | the composition dry-runs and deploys with `--env <environment>` itself and never read them; the `--env prod` in both misled |
| `ci.yml` gate | `vars.ORUN_CI == 'true'` | skip only while `intent.yaml` names `ws_CHANGE_ME` | a bootstrap cannot set a repository variable |
| `checks.yml` | push to main and pull requests | pull requests and `workflow_dispatch` | `orun.run/watch@v1` takes the newest run for a commit from ANY workflow |
| stack-tectonic / orun lane pin | 0.18.2 / v2.78.0 | 0.19.0 / v2.78.4 | the fleet's baseline pins (first-deploy and smoke retries; job-scoped install) |
| `intent.yaml` | terraform `parameterDefaults`; docs pages under `specs/`; no `infra/` or `packages/` root | none; docs pages `ai/context/*`; `infra/.gitkeep`, `packages/.gitkeep` | no terraform component; the pages must exist in a product; `orun validate` failed on the missing discovery roots |
| `tasks/EM-1..3` | no `metadata` | `metadata.name` and `title` | `orun work check` (v2.79) refused them |
| `maintenance-page.ts` | "(see design.md)" | the sentence alone | a product has no `design.md` |

## The cirrus standard (EM4)

Nothing about the recipes changed. What changed is the baseline around them:

| What | Before | After | Why |
|---|---|---|---|
| orun pin | `kiox.yaml` (v2.15.0) + `kiox.lock`, shipped to every product | gone; orun is pinned where it runs, the `orun-action` `version:` in each workflow | nothing ran the kiox pin, and it disagreed with the lanes (v2.78.4) |
| `root-kiox`, `root-kiox-lock` modules | in `01-product` | removed (`testing/phases.test.sh` and the rebrand's skip list follow) | a product is placed with 88 files: 84 − 2 kiox + 6 docs pages |
| component docs | none | `apps/recipes/docs/` and `tests/recipes/docs/` — `overview.md`, `architecture.md`, `runbook.md` | cirrus-baseline documents every component; the workspace Docs library renders `docs/` beside each `component.yaml` |
| how the docs stay true | — | `tooling/catalog/gen-component-docs.py` derives them from the manifest, the Worker config, Terraform, migrations and package scripts; Baseline CI runs it with `--check` | a hand-written copy of a manifest drifts silently |
| context pack | `operations.md`, `deployment.md` | plus `current.md`, `decisions.md`, `open-risks.md` | cirrus-baseline's shape; the three new pages are this repository's own and no module places them (the leak gate still allows exactly two) |
| status | EM3 "this PR (EM-4)"; the epic README "EM3 lands with EM-4" | EM3 shipped and tagged `baseline-v1` | the tag existed; the documents had not caught up |
| `ci.yml`'s gate in `design.md` §4 and the plan's sequencing note | "gated by the `ORUN_CI` variable" | plans nothing while `intent.yaml` names `ws_CHANGE_ME`; the basic-auth pair optional (its setup page until set) | EM3 replaced the variable; the documents still described it |

## Verified (EM4)

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer}.test.sh`
  green; `gen-component-docs.py --check` green (2 components, 6 pages).
- `orun new --status` at v2.58.11: `01-product` 88 files, `02-docs`
  hook-only.
- `testing/leak.test.sh` at v2.58.11: 88 files derived; ai/context still
  exactly the two declared pages; 83 shipped files read, none points at a
  factory path.
- `testing/placement.test.sh` at v2.58.11: 88 files placed, both landings,
  branded, re-tenanted; the product's own plan deploys `recipes` to stage
  and prod side by side; `--resume` changes nothing.
- `pnpm install --frozen-lockfile`, `wire:fixture` (the tree unchanged),
  `typecheck`, `lint`, `test` (15 files, 28 tests), `build` green.
- `testing/e2e.test.sh` at v2.78.4 green: the stage lane's six planned steps
  in a staged job tree, `wrangler dev --env stage`, the component's own
  smoke, the Rate Limiting binding, the index, all thirteen recipes and a
  404; with the basic-auth pair and the maintenance flag set, the challenge,
  a wrong pair, the right one and the maintenance page.
- `orun task check EM-5` complete.

## Verified (EM3)

- `orun new --status` reads the blueprint at v2.58.11 (the bootstrap floor),
  v2.78.4 (the lane pin) and v2.79.0; `orun validate` passes at all three;
  `orun work check` is clean (v2.79.0).
- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer}.test.sh`
  green. `phases` holds the two-phase partition (every module placed by
  `01-product`, `02-docs` hook-only, `01-product` the deploying phase) and the
  hook order; a reordered hook fails it.
- `testing/leak.test.sh` (v2.58.11 and v2.79.0): 84 files derived; nothing of
  the factory, nothing local or built, no provenance prose, and none of the
  79 shipped source files names a factory path (a planted
  `testing/e2e.test.sh` reference fails it).
- `testing/placement.test.sh` (v2.58.11 and v2.79.0; fixture "Sam's
  Middleware & More" / `acme-inc/acme-recipes`): the whole blueprint placed
  with the repo-scale gate; the offline bootstrap of BOTH phases, two
  landings; rebrand `--verify` clean; re-tenanted, `work:` stripped,
  promotion and dev lanes restored, record rendered; no tracked file names a
  factory path; the product's own `orun plan --trigger github-push-main` for
  the 01-product merge deploys `recipes` to stage and prod side by side, no
  infra to order before it, structure check before the build, the product's
  Worker, smoke and secret refs (brokered required, basic-auth optional);
  `--resume` changes nothing.
- `testing/e2e.test.sh` (v2.78.4 and v2.79.0): the 01-product landing passes
  the Checks sequence (install, wire, typecheck, lint, 28 tests, build) with
  the awkward name; the PR-trigger plan's stage lane — install,
  `verify-worker-structure`, `wire-fixture`, `build-worker`,
  `typecheck-worker`, `deploy-dry-run` — runs in a job tree staged from a
  pristine checkout (job-scoped install, no build output); `wrangler dev
  --env stage` serves it; the component's own smoke passes; the Rate
  Limiting binding refuses the sixth request; the index, all thirteen
  recipes, basic auth's setup page and a 404 answer as a fresh deploy serves
  them; with the pair and the maintenance flag set (`--var`), the challenge,
  a wrong pair, the right pair and the maintenance page.
- The repository's own checks: `pnpm install --frozen-lockfile`,
  `wire:fixture`, typecheck, lint, test (15 files, 28 tests), build.
- Not verified: a live bootstrap against a workspace (risks EM-K) — the
  repository created and linked, the brokered token, a real deploy, the
  probes. No infra exists, so nothing is planned or validated at the
  terraform level.

## Verified (EM1–EM2)

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
