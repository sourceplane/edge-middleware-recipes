#!/usr/bin/env bash
# TIER 1 — the tree is placed, branded, and made to answer.
#
# A real bootstrap is `orun new --run-hooks --resume` against a workspace: it
# places each phase, runs that phase's hooks, lands a pull request and watches
# the convergence. Everything in that sentence except the platform can run
# here, offline, and this file runs it:
#
#   1. the whole blueprint placed in one go — orun runs `validate` and
#      `plan --dry-run` inside the produced tree and says so; asserted, because
#      a future orun that stopped running them would weaken this tier in silence;
#   2. THE OFFLINE BOOTSTRAP (testing/lib/bootstrap.sh) — BOTH phases placed in
#      order, `02-docs` onto what `01-product` landed, each finished by the
#      blueprint's OWN `run:` hooks (the retouch marker, the rebrand, the
#      re-tenant, the work-tree strip, the deferrals and their restore, the
#      lockfile, the deployment record), each landing a commit;
#   3. the product it ends with: branded with no residue, carrying nothing of
#      the factory — no factory file, and no shipped file that names one —
#      re-tenanted, its gates restored, its record rendered;
#   4. what the product's own CI does with the 01-product merge: `orun plan`
#      for a push to main over exactly that commit, against a main that had
#      none of it — the Worker deployed to stage and prod side by side, nothing
#      on dev, anything under infra/ ordered before what reads its wiring (this
#      product has none, and the plan must say so), the Worker, the smoke and
#      the secret refs the product's own;
#   5. a `--resume` over the finished product places nothing and un-brands
#      nothing.
#
# testing/e2e.test.sh goes on from here: it installs, builds, dry-deploys and
# serves the product and runs its smoke against it.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git. No credential. The pnpm
# lockfile check and the deployment-record probes reach the network if they
# can, and pass without it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git; do
  command -v "$bin" >/dev/null || { echo "placement.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fails=0
fail() { echo "  ✕ $*" >&2; fails=$((fails + 1)); }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"

sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$values" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)

# ── 1. the whole blueprint, one placement ──────────────────────────────────
echo "── placing the whole blueprint at once (offline, no credential)"
whole="$scratch/whole"
mkdir -p "$whole"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$whole/$d/.gitkeep"; done
if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$whole" "${sets[@]}" > "$scratch/whole.log" 2>&1; then
  echo "FAIL: the placement did not run" >&2; tail -20 "$scratch/whole.log" >&2; exit 1
fi
# The line's wording moved between orun releases (v2.58: `repo gate: validate +
# plan --dry-run passed`; v2.79: `Verified  intent valid · N components …`).
grep -Eq "repo gate: validate \+ plan --dry-run passed|Verified +intent valid" "$scratch/whole.log" \
  || fail "the placement did not report the repo-scale gate (orun validate + plan --dry-run inside the tree)"
n="$(find "$whole" -type f -not -path '*/.orun/*' | wc -l | tr -d ' ')"
[ "$n" -ge 50 ] || fail "only $n files placed — that is not a product"
[ "$fails" -eq 0 ] && echo "   $n files placed; the repo-scale gate ran"

# ── 2. the offline bootstrap ───────────────────────────────────────────────
echo "── the offline bootstrap: both phases, their own hooks, a landing each"
tree="$scratch/$repo"     # named as the repository is: orun names the project after it
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
grep -E '^── ' "$scratch/bootstrap.log" | sed 's/^/  /'
commits="$(git -C "$tree" rev-list --count HEAD)"
[ "$commits" = 2 ] || fail "the bootstrap landed $commits commits, not one per phase (2)"

# ── 3. the product it ends with ────────────────────────────────────────────
echo "── the product it produced"
(cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" --verify --values .rebrand/values.json) > "$scratch/verify.log" 2>&1 \
  || { fail "rebrand --verify found the baseline's identity in the product:"; sed 's/^/      /' "$scratch/verify.log" >&2; }

python3 - "$tree" "$values" "$root" <<'PY' || fails=$((fails + 1))
import json, pathlib, re, subprocess, sys
import yaml
tree, values, root = pathlib.Path(sys.argv[1]), json.load(open(sys.argv[2])), pathlib.Path(sys.argv[3])
problems = []
def bad(m): problems.append(m)
repo, org, name, sub, ws = (values["reponame"], values["githuborg"], values["productname"],
                            values["subdomain"], values["orunWorkspace"])

tracked = subprocess.run(["git", "ls-files"], cwd=tree, capture_output=True, text=True, check=True).stdout.split()

# Nothing of the factory, nothing local, exactly the two context pages.
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", "tooling/migrations/",
         ".github/workflows/baseline.yml", ".github/workflows/tag.yml", "BOOTSTRAP.md",
         "repo-blueprint.yaml", "blueprint.yaml")
for p in tracked:
    if any(p == n or p.startswith(n) for n in NEVER):
        bad(f"{p} is in the product — it is the factory")
    if re.search(r"(^|/)(\.env(\.local)?|\.dev\.vars(\.(?!example$)[^/]*)?|node_modules|\.orun|\.wrangler|dist)(/|$)", p):
        bad(f"{p} is in the product — a local or built file")
ai = {p for p in tracked if p.startswith("ai/")}
if ai != {"ai/context/deployment.md", "ai/context/operations.md"}:
    bad(f"ai/ in the product is {sorted(ai)}")
for must in ("apps/recipes/.dev.vars.example", ".rebrand/values.json", "infra/.gitkeep", "packages/.gitkeep"):
    if must not in tracked:
        bad(f"{must} is not in the product")

# No shipped file — branded, as the product has it — sends its reader to a
# factory path the product does not have.
FACTORY_PATH = re.compile(r"repo-blueprint|BOOTSTRAP\.md|(?<![\w.@/-])\.?baseline/|"
                          r"(?<![\w.@-])(testing|specs|tasks|docs/phases)/")
for p in tracked:
    try:
        text = (tree / p).read_text(errors="replace")
    except IsADirectoryError:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        m = FACTORY_PATH.search(line)
        if m:
            bad(f"{p}:{n} names {m.group(0)!r}: {line.strip()[:70]}")

# The identity, where the product carries it.
site = (tree / "apps/recipes/src/site.ts").read_text()
if f"SITE_NAME = {json.dumps(name)};" not in site:
    bad(f"apps/recipes/src/site.ts does not name the product {name!r}")
if f'SOURCE_URL = "https://github.com/{org}/{repo}";' not in site:
    bad(f"apps/recipes/src/site.ts does not link github.com/{org}/{repo}")
wrangler = (tree / "apps/recipes/wrangler.jsonc").read_text()
if not re.search(rf'^\s*"name": "{re.escape(repo)}-recipes",$', wrangler, re.M):
    bad(f"wrangler.jsonc does not name the Worker {repo}-recipes")
comp = yaml.safe_load((tree / "apps/recipes/component.yaml").read_text())["spec"]
if f"https://{repo}-recipes-${{ORUN_ENVIRONMENT}}.{sub}.workers.dev" not in comp["parameters"]["smokeCommand"]:
    bad(f"the smoke does not probe the product's Worker: {comp['parameters']['smokeCommand'][:120]}")
for key in ("BASIC_AUTH_USER", "BASIC_AUTH_PASSWORD"):
    want = f"secret://{ws}/{repo}/{{{{ .environment }}}}/{key}"
    if (comp.get("optionalSecretEnv") or {}).get(key) != want:
        bad(f"optionalSecretEnv.{key} is {(comp.get('optionalSecretEnv') or {}).get(key)!r}, not {want!r}")
if json.loads((tree / "package.json").read_text())["name"] != repo:
    bad("package.json is not named for the product")

# The intent: re-tenanted, no work tree, both gates back.
intent_text = (tree / "intent.yaml").read_text()
intent = yaml.safe_load(intent_text)
if intent["metadata"]["name"] != repo:
    bad(f"intent metadata.name is {intent['metadata']['name']}")
if intent["execution"]["state"]["workspace"] != ws:
    bad(f"intent workspace is {intent['execution']['state']['workspace']}, not the product's")
if "work" in intent:
    bad("intent.yaml still declares the baseline's work tree")
if "promotion" not in intent["environments"]["prod"] or "@promotion-deferred" in intent_text:
    bad("prod's promotion gate was not restored by 02-docs")
if "github-push-main" not in intent["environments"]["dev"]["activation"]["triggerRefs"] or "@dev-lanes-deferred" in intent_text:
    bad("dev's push activation was not restored by 02-docs")
for env in ("stage", "prod"):
    want = f"https://{repo}-recipes-{env}.{sub}.workers.dev"
    if intent["environments"][env].get("url") != want:
        bad(f"environments.{env}.url is {intent['environments'][env].get('url')}, not {want}")
for page in (intent.get("repo") or {}).get("docs", {}).get("pages", []):
    if not (tree / page["path"]).exists():
        bad(f"intent repo.docs names {page['path']}, which the product does not have")

# The landings, as the phases made them.
for c in ("apps/recipes/component.yaml", "tests/recipes/component.yaml"):
    if not re.search(r"^# orun: redeploy 01-product \S+$", (tree / c).read_text(), re.M):
        bad(f"{c} carries no 01-product redeploy marker")
dep = (tree / "ai/context/deployment.md").read_text()
if "GENERATED by the `02-docs` phase" not in dep or f"https://{repo}-recipes-prod.{sub}.workers.dev" not in dep:
    bad("ai/context/deployment.md was not rendered for the product")
readme = (tree / "README.md").read_text()
if not readme.startswith(f"# {repo}\n") or "This product is **live**" not in readme:
    bad("README.md is not the product's, or its live-deployment section was not rendered")

# Provenance prose, over the BRANDED files.
PROV = re.compile(r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|repo-blueprint|BOOTSTRAP\.md", re.I)
for rel in ("README.md", "ai/context/operations.md", "ai/context/deployment.md"):
    for n, line in enumerate((tree / rel).read_text().splitlines(), 1):
        if PROV.search(line):
            bad(f"{rel}:{n} speaks of the factory: {line.strip()[:70]}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {len(tracked)} tracked files; branded, re-tenanted, gates restored, record rendered; none names a factory path")
PY

# ── 4. the product's own CI, over the 01-product merge ─────────────────────
# 01-product is the product's FIRST commit; the main it merges into has none
# of it. That base is stood in for by an empty commit, so `--changed` sees
# every file the landing adds — what the real merge's push plans.
echo "── orun plan in the product, for the push that merged 01-product"
s01="$(git -C "$tree" rev-parse HEAD~1)"
empty="$(git -C "$tree" commit-tree "$(git -C "$tree" hash-object -t tree /dev/null)" -m "main before the product")"
git -C "$tree" checkout -q "$s01"
(cd "$tree" && orun validate --intent intent.yaml) > "$scratch/validate.log" 2>&1 \
  || { fail "orun validate refused the product's intent at 01-product"; tail -10 "$scratch/validate.log" >&2; }
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --changed \
   --base "$empty" --head "$s01" --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { fail "orun plan failed in the product at 01-product"; tail -15 "$scratch/plan.log" >&2; }
git -C "$tree" checkout -q main
python3 - "$scratch/plan.json" "$values" "$tree" <<'PY' || fails=$((fails + 1))
import json, pathlib, sys
import yaml
plan, values, tree = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), pathlib.Path(sys.argv[3])
repo, sub, ws = values["reponame"], values["subdomain"], values["orunWorkspace"]
problems = []
def bad(m): problems.append(m)
jobs = {(j["component"], j["environment"]): j for j in plan["jobs"]}
by_id = {j["id"]: j for j in plan["jobs"]}
if set(jobs) != {("recipes", "stage"), ("recipes", "prod")}:
    bad(f"the 01-product merge plans {sorted(jobs)}; it must deploy recipes to stage and prod and "
        f"nothing else (dev's push lanes are deferred, and recipes-tests is dev-only)")

# INFRA BEFORE APP: every job of a component under infra/ comes before every
# job in its environment that reads its wiring (an enforced dependsOn on main).
# This product has no infra — then the plan must hold no infra job, and the
# Worker waits on nothing in its own environment.
infra = {c for c, _ in jobs if (tree / "infra" / c / "component.yaml").exists()}
for (comp, env), j in jobs.items():
    deps = [by_id[d] for d in (j.get("dependsOn") or []) if d in by_id]
    for i in infra:
        if (i, env) in jobs and comp not in infra and jobs[(i, env)]["id"] not in (j.get("dependsOn") or []):
            bad(f"{comp}@{env} does not wait on {i}@{env}")
    if not infra and deps:
        bad(f"{comp}@{env} waits on {[d['id'] for d in deps]} — with no infra and the promotion gate "
            f"deferred, stage and prod deploy side by side")

for (comp, env), j in jobs.items():
    if not j["profile"].endswith(".deploy"):
        bad(f"{comp}@{env} plans profile {j['profile']}, not a deploy")
    order = [s["id"] for s in j["steps"]]
    steps = {s["id"]: s.get("run") or "" for s in j["steps"]}
    for need in ("verify-worker-structure", "build-worker", "deploy", "secrets-live", "smoke"):
        if need not in steps:
            bad(f"{comp}@{env} has no {need} step")
    if "verify-worker-structure" in order and "build-worker" in order and \
            order.index("verify-worker-structure") > order.index("build-worker"):
        bad(f"{comp}@{env} checks its structure after the build")
    if "test -f \"wrangler.jsonc\"" not in steps.get("verify-worker-structure", ""):
        bad(f"{comp}@{env}'s structure check does not require the committed wrangler.jsonc")
    if f"--env {env}" not in steps.get("deploy", ""):
        bad(f"{comp}@{env} does not deploy with --env {env} (the Worker {repo}-recipes-{env})")
    if f"https://{repo}-recipes-${{ORUN_ENVIRONMENT}}.{sub}.workers.dev" not in steps.get("smoke", "") \
            or "/json-response" not in steps.get("smoke", ""):
        bad(f"{comp}@{env}'s smoke is not the product's")
    if "BASIC_AUTH_USER,BASIC_AUTH_PASSWORD" not in steps.get("secrets-live", ""):
        bad(f"{comp}@{env}'s secrets-live does not push the basic-auth pair")
    refs = {r["asEnv"]: r for r in j.get("secretRefs") or []}
    for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
        ref = (refs.get(key) or {}).get("ref", "")
        if not ref.startswith(f"secret://{ws}/") or f"project:{repo}" not in ref or (refs.get(key) or {}).get("optional"):
            bad(f"{comp}@{env} resolves {key} from {ref or 'nowhere'} — not the product's workspace and project, required")
    for key in ("BASIC_AUTH_USER", "BASIC_AUTH_PASSWORD"):
        r = refs.get(key) or {}
        if r.get("ref") != f"secret://{ws}/{repo}/{env}/{key}" or not r.get("optional"):
            bad(f"{comp}@{env} resolves {key} as {r or 'nothing'} — not an optional ref on the product's {env} rung")
if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   recipes → stage + prod, deploy, side by side; no infra, so nothing to order before the Worker")
print(f"   structure check before the build; Worker, smoke and secret refs the product's own")
PY

# ── 5. a resume over the finished product ─────────────────────────────────
echo "── --resume over the finished product"
before="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" --resume "${sets[@]}" > "$scratch/resume.log" 2>&1 \
  || { fail "--resume did not run"; tail -10 "$scratch/resume.log" >&2; }
after="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
[ "$before" = "$after" ] || { fail "--resume changed the finished product:"; git -C "$tree" status --short | head -10 >&2; }
grep -q "SITE_NAME = \"Sam's Middleware & More\"" "$tree/apps/recipes/src/site.ts" \
  || fail "--resume reverted the product's identity"
[ "$fails" -eq 0 ] && echo "   nothing placed again, nothing un-branded"

[ "$fails" -eq 0 ] || { echo "placement.test.sh: $fails failure(s)" >&2; exit 1; }
echo "placement.test.sh: ok"
