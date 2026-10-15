# edge-middleware-recipes — risks and open questions

## EM-A — The Rate Limiting binding is not Upstash's sliding window (ACCEPTED)

The upstream's `Ratelimit.slidingWindow(5, '10 s')` is exact and global
(Redis). The Workers Rate Limiting binding is per Cloudflare location,
"permissive, eventually consistent", with a fixed 10 s or 60 s period, and
returns `success` only. For the recipe's rule — block the sixth request from
one IP within ten seconds — that is the right trade: no round trip, nothing to
provision, simulated by `wrangler dev`. A rule that must be exact across the
world is a Durable Object (the baseline's `api-edge` carries that pattern);
the design names it as the rejected alternative.

## EM-B — `namespace_id` is account-wide (OPEN until linked)

Rate limiting bindings that share a `namespace_id` share counters across every
Worker in the account. The port uses `1001`–`1004` (local, dev, stage, prod).
Another Worker in the target account using the same ids would share this
recipe's counters. Pick ids per product when instantiating; nothing in the
repository can know the account.

## EM-C — A 5 MB redirect table in the bundle (RESOLVED)

`redirects.json` is 5.1 MB and the generated Bloom filter 0.6 MB. The bundle is
6.3 MiB raw, 550 KiB gzipped — the limit that applies is the compressed one
(3 MiB free, 10 MiB paid). The table is a dynamic import, which esbuild
wraps in a lazy `require_redirects()`; it is parsed on the first Bloom hit,
not at isolate start, which keeps startup within the 400 ms CPU budget the
way the upstream's middleware/Route Handler split does on Vercel. Measured
under `wrangler dev`: the first hit answers in 25 ms, later hits in 20 ms.

## EM-D — `bloom-filters` 3.x pulls lodash and reflect-metadata (RESOLVED)

The upstream lists both under `unstable_allowDynamic` because each contains
`Function('return this')`, which a Worker would refuse at run time. Both calls
are guarded — `typeof global`/`typeof self` are checked first — and `self`
exists on workerd, so the branch never runs. Verified: the filter loads and
answers under `wrangler dev`.

## EM-E — `request.cf` is absent off Cloudflare (RESOLVED)

Node's `Request` has no `cf`, so the geolocation and i18n middlewares see
nothing in unit tests, exactly as the upstream sees nothing off Vercel; they
fall back to US / San Francisco / `en-US` as written. The tests put a `cf`
object on the Request (`Object.defineProperty`) to exercise the real path.
`wrangler dev` fetches the machine's own `cf` from Cloudflare, so the local
demo shows real data.

## EM-F — The basic-auth secrets are not created by the deploy lane (OPEN)

`cloudflare-worker-turbo` deploys the Worker; it does not set secrets.
`BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` must be `wrangler secret put` per
environment before the first deploy, or the recipe answers 401 to everyone
(safe, but not the demo). The README says so; `.dev.vars.example` carries the
upstream's demo pair for local work only.

## EM-G — wrangler's multi-environment warning on the local build (ACCEPTED)

`wrangler.jsonc` carries `env.dev`, `env.stage` and `env.prod` because the
composition deploys with `--env`. A bare `wrangler deploy --dry-run` (the
`build` script) warns that no target environment was given and bundles the
top level (`ENVIRONMENT=local`). Intended; Orun's lanes always pass `--env`.

## EM-H — Rewrites that re-enter their own middleware (RESOLVED)

`rewrite()` re-dispatches to the recipe's router, so a rewrite whose target is
the matcher's own path would loop. Every rewrite targets a path the matcher
does not cover; geolocation — the one upstream rewrite that aims back at `/`
with a query — aims at `/index`, which Next also serves `pages/index.tsx` at.

## EM-I — `ua-parser-js` licence (RESOLVED)

`ua-parser-js` 2.x is AGPL; 1.x — the line Next bundles for `userAgent()` —
is MIT. The port pins `^1.0.40` (1.0.41 verified) and types it with
`@types/ua-parser-js`.

## EM-J — The brief expected `negotiator` + `@formatjs/intl-localematcher` for i18n (RESOLVED)

The upstream i18n example at `ecee781` does not use them: its locale is the
first entry of `Accept-Language`, unparsed. The port follows the code, not the
brief; the Next docs' `negotiator` pattern is a one-line swap in the
middleware if a product wants real negotiation.
