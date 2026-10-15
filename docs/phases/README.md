# The phases — one blueprint, two selections

`repo-blueprint.yaml` declares two phases that take a product from
**nothing** to **live on stage and prod, documented**: `01-product` builds the
whole product in ONE landing, and `02-docs` records what went live. Run them
one at a time with `--phase <name>`, or the whole sequence unattended with
`--resume`. There is no umbrella workflow and no per-phase document: a phase
is a selection on one artifact, which is what makes running one alone, months
later, from a fresh container the same operation as running them all.

Each phase follows the same contract:

> **place its modules → brand them → land them as one pull request → watch
> the convergence that merge triggers (auto-resumed) → verify the outcome
> over HTTP.**

Run from the baseline checkout (the blueprint's source is `path: .`); the
product's repository is wherever `--out` points.

## Execution order

The phase number is the EXECUTION order, and `02-docs`'s `requires.phases`
states it in the document: the engine refuses a phase whose predecessor is not
placed, and names it.

Every landing is a pull request on a branch named for its task
(`orun/BASE-<n>-<phase>`). On those branches `ci.yml` runs `plan` only — the
intent, every component and every composition resolve — and skips the lanes,
because the merge runs them on main a minute later, for real, and that
convergence is what `01-product` watches. `checks.yml` (install, typecheck,
lint, test, build) runs on every pull request regardless.

| phase | lands | verified by |
|---|---|---|
| [`01-product`](01-product.md) | **the GitHub repo created**, then the WHOLE product in one PR: intent, CI, tooling, identity, `apps/recipes` and `tests/recipes`; one convergence deploys the Worker to stage and prod side by side | convergence green (structure check, build, typecheck, deploy, smoke) + both workers.dev URLs answer |
| [`02-docs`](02-docs.md) | the live-deployment record; the promotion gate and dev lanes put back | committed manifest matches probed reality |

There is no custom-domain phase. Attaching a domain to a Worker needs zone
permissions the platform's brokered `workers-deploy` token does not carry, so
it is an owner's step after the bootstrap — the product's README, "Custom
domain", says how. No recipe builds absolute links to itself, so nothing in
the code changes with it.

There is no infra either: the Worker's bindings are vars, a rate limiting
binding `wrangler deploy` creates, and owner-seeded secrets. Nothing is
provisioned before the Worker, nothing lease-publishes a `WIRING_*` secret,
and `01-product`'s await has no secrets check.

## Inputs

`01-product` takes the product's identity once and writes it into the repo
(`.rebrand/values.json`); `02-docs` reads it back from the placed tree. But
the blueprint's **required** inputs — `reponame`, `productname`,
`productdomain`, `githuborg` — are validated before any phase runs, so they
must be supplied on every invocation, single-phase ones included. A
`--values` file is easier than repeating `--set`.

- `subdomain` — the workers.dev subdomain of the Cloudflare account. It is
  in every URL the phases probe and in the deploy's smoke.
- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`); with none anywhere, a placeholder that
  fails loudly rather than silently claiming another tenant's workspace.
- `epicSlug` (default `edge-middleware-recipes-baselining`) — the epic every
  phase clubs its task under. Found by slug, so a fresh run and a resumed run
  find the same work.
- `repoPrivate` (default `true`) — the repository's visibility at creation.

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/products/acme-recipes --run-hooks --phase 01-product \
  --values ~/acme-recipes.values.yaml
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh`,
`testing/e2e.test.sh`).

## What `01-product` does after it places

Placement writes the baseline's files as they are here. Before the phase
lands, its `post` hooks make them the product's:

1. `retouch` — one `# orun: redeploy <phase> <stamp>` line at the end of each
   component.yaml its task contract names, so a re-run after a failed
   convergence still has a diff to land and redeploys exactly those
   components.
2. `git-init`, `git-stage`, then `rebrand` — the identity rename over the
   whole tree — and `orun-workspace`, which writes the product's workspace
   into `intent.yaml`.
3. `work-tree --strip` (the baseline's `work:` block does not ship),
   `promotion --defer` and `dev-lanes --defer` (stage and prod deploy side by
   side, and dev stays off main, until `02-docs` puts both back).
4. `git-restage`, `rebrand --verify` — a sweep that fails on any of this
   baseline's identity left behind.
5. `pnpm install --lockfile-only` — confirms the complete lockfile
   `root-pnpm-lock` placed.
6. `orun.repo/ensure@v1`, then `link` — the repository exists and is the
   workspace's before anything lands in it.
7. `orun.integrations/reconcile@v1`, once per brokered key —
   `CLOUDFLARE_API_TOKEN` (`workers-deploy`) and `CLOUDFLARE_ACCOUNT_ID`
   (`account-id`).
8. `orun.pr/land@v1` — the one pull request, merged once its checks are green.

`testing/phases.test.sh` holds this order.

## When a phase fails

- **Before it lands** (a probe that timed out, a rebrand residue, a refused
  link): nothing was merged. Fix what the message names and re-run the phase.
- **After it lands** (the convergence went red): the files are on main.
  `orun.run/watch@v1` has already resumed the run up to three times. Re-run
  the phase (`--phase 01-product`, `--redo 01-product` under `--resume`, or
  the console's Retry): its `retouch` hook gives the landing a diff and the
  components redeploy.
