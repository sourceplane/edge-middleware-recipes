# edge-middleware-recipes — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/edge-middleware-recipes/risks-and-open-questions.md`; this page
lists only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| EM-K | No live bootstrap yet: the repository created and linked, the brokered token, a real `wrangler deploy` (including that `workers-deploy` covers a Rate Limiting binding and `wrangler secret bulk`), the smoke and the probes are all unproven | OPEN | One bootstrap from a tag against a workspace |
| EM-B | Rate-limit `namespace_id`s (1001–1004) are account-wide and the rebrand keeps them, so two products in one account share counters | OPEN until linked | The owner gives a second product in the same account its own ids (README, BOOTSTRAP.md) |

Accepted, and worth knowing before you change them: EM-A (the binding is not
Upstash's sliding window), EM-G (wrangler's multi-environment warning on the
local build), EM-L (a custom domain is the owner's step), EM-M (the first
landing has no base).
