# BOOTSTRAP — a new product from this baseline, in one landing

How to go from **nothing** to **the Edge Middleware recipes live on stage and
prod, documented**, with ONE provider consent.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets and the programme, and `testing/manifest.test.sh` holds it
to what the build document does.

Target wall-clock: **about eight minutes** — an estimate summed from the
phases until a bootstrap measures it: ONE landing that places and brands the
whole product, whose pull request waits on Checks and `plan`; ONE
convergence that deploys the Worker to stage and prod side by side (a
wrangler bundle each, no framework build); then the deployment record.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.58.11** — the floor for RUNNING the bootstrap (the phase overlay,
  landings that commit per phase and wait on the PR's whole CI run,
  `githubOwner` on the doctor probe, a probe deferred for a project not yet
  created, and `from: workspace`). The product's own `ci.yml` pins its lanes
  separately (v2.78.4).
- A Cloudflare account (the Worker's bundle is about 550 KiB gzipped, inside
  the free plan's size limit) and its **Account API token** with Workers
  Scripts Write (the console's Connect recipe lists the exact permission
  groups). It is the ONLY provider credential this baseline needs.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the
  workspace the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-product`'s `link` step
  stops and names the fix if it is not.

No third-party key, and nothing the platform cannot broker: the basic-auth
recipe's pair (`BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`) is the product
owner's to set AFTER the bootstrap (§3), and until it is, that one recipe
answers a setup page. Every other recipe works on the first deploy.

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/edge-middleware-recipes
cd edge-middleware-recipes

orun new --blueprint repo-blueprint.yaml \
  --out ~/products/acme-recipes --run-hooks --resume \
  --set reponame=acme-recipes --set productname="Acme Recipes" \
  --set productdomain=acme.dev --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the product's identity.

## 1b. Or phase by phase

| phase | what it lands | verified by |
|---|---|---|
| `01-product` | the repository, created and linked; the brokered Cloudflare secrets; then ONE pull request with everything — intent, CI, tooling, identity, `apps/recipes`, `tests/recipes` | its PR's checks green, merged; the convergence green (structure check, build, typecheck, deploy, smoke on stage and prod); both workers.dev URLs answering |
| `02-docs` | `ai/context/deployment.md` from probed facts; prod's promotion gate and dev's push lanes restored | the final probe |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-recipes --run-hooks \
  --phase 01-product --values ~/acme-recipes.values.yaml
# … then 02-docs
```

`02-docs` reads the identity back from `.rebrand/values.json` in the placed
tree, but the blueprint's **required** inputs — `reponame`, `productname`,
`productdomain`, `githuborg` — are validated before anything runs, so pass
them every time (a `--values` file is easier). The full guide, one page per
phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops |

What lands in the product is PRODUCT-ONLY: the Worker, its tests, its CI,
its tooling, its README and its two context pages. None of this repository's
machinery (`.baseline/`, the blueprints, `tooling/rebrand`,
`tooling/bootstrap`, `tooling/migrations`, `hooks/`, `testing/`,
`docs/phases/`, `specs/`, `tasks/`, this file) ships, and no shipped file
names one of those paths. That promise is a test: `testing/leak.test.sh`
derives what every phase would place and gates the set and every file's
content, and `testing/placement.test.sh` gates the same rules over a placed,
branded tree.

## 2. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/edge-middleware-recipes
cd edge-middleware-recipes
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-recipes --run-hooks --resume --progress json \
  --values /work/acme-recipes.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the PRODUCT's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-product` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 3. After the product is live

- **Turn on basic auth**: `orun secrets set BASIC_AUTH_USER --env stage`
  and `BASIC_AUTH_PASSWORD` (and `--env prod`), then redeploy by editing the
  last line of `apps/recipes/component.yaml` — the deploy's `secrets-live`
  step pushes every seeded secret to the Worker. `wrangler secret put` works
  too. The product's README, "Secrets".
- **Change or add a recipe**: `apps/recipes/src/recipes/<name>.ts` and its
  test in `tests/recipes/src/`; the product's name and source link are
  `apps/recipes/src/site.ts`. Every merge to `main` redeploys.
- **Rate limiting namespaces**: `namespace_id` 1001–1004 in
  `apps/recipes/wrangler.jsonc` are account-wide. A second product in the
  same Cloudflare account should get its own ids, or the two share counters.
- **Custom domain**: attach it to the Worker in Cloudflare (the product's
  README, "Custom domain"). There is no domain phase: attaching a domain
  needs zone permissions the brokered `workers-deploy` token does not carry,
  and no recipe builds absolute links to itself.
- **Refresh the record**: re-run `--phase 02-docs`; it is idempotent.

## 4. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun, node, pnpm: the offline bootstrap
bash testing/e2e.test.sh         # + network for pnpm: the product built, dry-deployed and served
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places both phases in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the retouch marker, the rebrand,
the re-tenant, the work-tree strip, the deferrals and their restore, the
lockfile and the deployment record all run exactly as a real bootstrap runs
them. Only the platform's typed actions (task, repo, link, land, watch,
probe, reconcile) are stood in for, a landing becoming a commit. The e2e
then runs the stage lane's steps exactly as the product's pull-request plan
renders them — the structure check included — in the job tree orun stages,
and serves the Worker with `wrangler dev`.

## 5. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag, so
the tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then add (or move) the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-product` parks: `waiting for github for <org>` | the workspace's GitHub connection is to another account. Connect the App installation on `<org>` (console → Integrations → GitHub), then `--resume` |
| `01-product` parks on Cloudflare | Cloudflare is not connected. Connect it (console → Integrations) while the probe waits — it is a wait, not a failure |
| `01-product` stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| Deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts Write; re-issue it, re-connect, re-run `01-product` |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 01-product`, `--redo 01-product`, or the console's Retry): its `retouch` hook gives the landing a diff and the Worker redeploys |
| The product's `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace; set it and re-run `01-product` |
| A bootstrap stopped before `02-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `02-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <product>/intent.yaml` |
| `/basic-auth-password` answers 503 on the live product | expected until the owner sets the pair (§3) |
| `✕ input "productdomain" is required` | all four required inputs must be set on every invocation, single-phase ones included |
| `unknown flag: --phase` or a parse error in the blueprint | the CLI is below the v2.58.11 floor |
| The convergence reported green, then `verify` got 404 from both URLs | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` runs on a push to main (`checks.yml` is pull-request only); read the CI run on main for the real result |
