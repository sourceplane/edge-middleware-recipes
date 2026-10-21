# edge-middleware-recipes — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's thirteen Edge Middleware examples (geolocation, i18n, basic auth,
rate limiting, A/B testing, a maintenance page, cookies, headers, query
filtering, a JSON response, user-agent rendering, bloom-filter redirects)
ported as recipes of ONE plain Cloudflare Worker, Hono-routed, each with its
upstream behaviour and a test. It is packaged as an Orun baseline:
`orun new --blueprint repo-blueprint.yaml` builds a new product in its own
repository and takes it to live on stage and prod in one landing
(`01-product`), then records what went live (`02-docs`). There is no
infrastructure: nothing to provision, nothing to wire.

## Release

| | |
|---|---|
| Latest tag | `baseline-v2` (EM4 — the cirrus standard: no kiox, generated component docs, this context pack, and the workers.dev subdomain read from the Cloudflare connection instead of asked) |
| Before it | `baseline-v1` (EM3, [#4](https://github.com/sourceplane/edge-middleware-recipes/pull/4)) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the stage lane run in orun's staged job tree, `wrangler dev --env stage` serving every recipe, the Rate Limiting binding refusing the sixth request, the component's own smoke. No bootstrap from a tag has run against a workspace: the repository link, the brokered token, a real `wrangler deploy` and the probes are unproven (risk EM-K) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/edge-middleware-recipes/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/edge-middleware-recipes/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/edge-middleware-recipes/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `apps/recipes/docs/`, `tests/recipes/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v2` against a workspace, and record
   its timings (closes EM-K); then the registry row can go public.
