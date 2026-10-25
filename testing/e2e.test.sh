#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, deploys (dry) and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      the landing's own checks — install with the lockfile the product
#      ships, render fixtures, typecheck, lint, test, build. The landing is
#      checked in the box with `orun validate` and `orun plan` alone
#      (`checks: local`; its PR's CI on an `orun/BASE-*` branch is `plan`
#      alone), and a later pull request of the product runs ci.yml's verify
#      lanes, which build, type-check and dry-deploy the Worker but neither
#      lint nor test it — so THIS is where a product those steps refuse is
#      caught: before the tag, not after a build has merged it. 02-docs, the
#      only later landing, must touch nothing those checks read, so the
#      finished product passes them too;
#   2. the stage lane's own steps, EXACTLY as the product's `orun plan` for
#      that pull request renders them (the PR-trigger plan: `deploy-dry-run`
#      is not in the deploy profile, so it is the plan that carries every
#      non-mutating step) — every `run:` step of the job, in order: the
#      install, `verify-worker-structure` (package.json and the COMMITTED
#      wrangler.jsonc, checked BEFORE the build), `wire-fixture`,
#      `build-worker`, `typecheck-worker` and `deploy-dry-run` (`wrangler
#      deploy --dry-run --env stage`). They run IN THE TREE THE RUNNER STAGES
#      for the job (testing/lib/stage-job.py) — no build output, nothing git
#      ignores — with the dependency layout the pinned composition produces;
#   3. serve the staged Worker with `wrangler dev --env stage` and run the
#      component's OWN `smokeCommand` against it, verbatim — the check the real
#      deploy ends with — then read every route the product promises, as a
#      fresh deploy has it (no secret set): the index carries the product's
#      name and source link, each of the thirteen recipes does what it says
#      (geolocation, i18n, basic auth's setup page, the rate limit, A/B
#      buckets, the maintenance flag, cookies, response and request headers,
#      query filtering, JSON, user-agent rendering, Bloom-filter redirects), an
#      unknown path is a 404 — and the one only the Worker can answer: the
#      Workers Rate Limiting binding, which the unit tests stand in for with a
#      fake, refusing the sixth request in ten seconds;
#   4. serve it again as its owner configures it — the basic-auth pair set
#      and the maintenance flag on (`wrangler dev --var`) — and read the
#      challenge, a wrong pair, the right pair and the maintenance page.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, deploy for real and probe workers.dev. That is a
# bootstrap against a workspace (BOOTSTRAP.md); everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, setsid, and the
# network for `pnpm install` (or a warm store). A few minutes: two installs
# and two Worker bundles (the landing's checks over the product, and the
# stage lane's own in its staged tree).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl setsid; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
tree=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
stop_dev() {
  if [ -n "$dev_pid" ]; then
    kill -TERM -- "-$dev_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL -- "-$dev_pid" 2>/dev/null || true
    dev_pid=""
  fi
}
cleanup() {
  stop_dev
  [ -n "$tree" ] && git -C "$tree" worktree prune 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step, run here at once on the whole
# tree. A pull request in the product builds, type-checks and dry-deploys the
# Worker through ci.yml's lanes; the lint and the tests run here, and by hand
# before a push.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# A free port for each wrangler dev, so a run never collides with another
# (or with a developer's own wrangler dev on 8787).
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }

start_dev() { # DIR LOG [wrangler dev args…]
  local dir="$1" log="$2"; shift 2
  local port; port="$(free_port)"
  (cd "$dir" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --env stage \
     --ip 127.0.0.1 --port "$port" --show-interactive-dev-session=false "$@") > "$log" 2>&1 < /dev/null &
  dev_pid=$!
  url="http://127.0.0.1:$port"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$url/" && return 0
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$log" >&2; return 1; }
    sleep 1
  done
  echo "FAIL: wrangler dev never answered" >&2; tail -30 "$log" >&2; return 1
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"
s01="$(git -C "$tree" rev-parse HEAD~1)"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
later="$(git -C "$tree" diff --name-only "$s01" HEAD)"
echo "   02-docs then changed: $(echo $later)"
while IFS= read -r f; do
  case "$f" in
    intent.yaml|README.md|ai/context/*) ;;
    *) echo "FAIL: 02-docs changed $f, which the product's checks read — they must run on the finished product too" >&2; exit 1 ;;
  esac
done <<< "$later"

# ── 2. the stage lane's steps, as the PR-trigger plan renders them ─────────
echo "── the stage lane, every step the product's PR plan renders, in a staged job tree"
# The product's first pull request lands into a main that has none of it; an
# empty commit stands in for that base, so `--changed` sees every file.
empty="$(git -C "$tree" commit-tree "$(git -C "$tree" hash-object -t tree /dev/null)" -m "main before the product")"
(cd "$scratch/at-01" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$empty" --head "$s01" --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
python3 - "$scratch/plan.json" "$scratch/steps" <<'PY'
import json, pathlib, sys
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
job = next((j for j in plan["jobs"] if j["component"] == "recipes" and j["environment"] == "stage"), None)
if job is None:
    sys.exit(f"FAIL: the product's PR plan has no recipes@stage job: {[j['id'] for j in plan['jobs']]}")
if not job["profile"].endswith(".verify"):
    sys.exit(f"FAIL: recipes@stage plans {job['profile']} on a pull request, not the verify profile")
order = []
for i, s in enumerate(job["steps"]):
    if s.get("use"):
        print(f"   · {s['id']}: {s['use']} — this runner's own node and pnpm stand in")
        continue
    stem = f"{i:02d}-{s['id']}"
    (out / f"{stem}.sh").write_text(s.get("run") or "")
    (out / f"{stem}.wd").write_text(s.get("working-directory") or ".")
    (out / f"{stem}.scope").write_text(s.get("scope") or "job")
    order.append(s["id"])
for need in ("install-workspace-dependencies", "verify-worker-structure", "wire-fixture",
             "build-worker", "typecheck-worker", "deploy-dry-run"):
    if need not in order:
        sys.exit(f"FAIL: the stage lane has no {need} step: {order}")
if order.index("verify-worker-structure") > order.index("build-worker"):
    sys.exit("FAIL: the structure check runs after the build")
(out / "order").write_text("\n".join(order) + "\n")
(out / "path").write_text(job.get("path") or "apps/recipes")
(out / "jobid").write_text(job["id"])
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
print(f"   the plan's run steps: {', '.join(order)}")
PY
path="$(cat "$scratch/steps/path")"

# THE CONFIG THE STRUCTURE CHECK REQUIRES IS COMMITTED. A config that only a
# build generates is absent from the staged tree when the check runs.
wcfg="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['wranglerConfig'])" "$tree/$path/component.yaml")"
git -C "$tree" ls-files --error-unmatch "$path/$wcfg" > /dev/null 2>&1 \
  || { echo "FAIL: the component's wranglerConfig $path/$wcfg is not a committed file" >&2; exit 1; }

# The job's private tree, staged as orun stages it, from a PRISTINE checkout
# of the landing — what actions/checkout gives a lane: no node_modules, no
# build output, nothing git ignores (orun would copy a `.wrangler` it found;
# a fresh checkout has none). The dependencies are what the pinned
# composition says: a lane-scoped install runs once in that source tree and is
# linked in, or the job's own install step runs inside its staged tree.
git -C "$tree" worktree add -q "$scratch/src-01" "$s01"
src="$scratch/src-01"
lane_scoped=false
for f in "$scratch"/steps/*.scope; do [ "$(cat "$f")" = lane ] && lane_scoped=true; done
work="$src/.orun/runs/e2e/$(cat "$scratch/steps/jobid")/work"
if $lane_scoped; then
  for f in "$scratch"/steps/[0-9][0-9]-*.scope; do
    [ "$(cat "$f")" = lane ] || continue
    stem="$(basename "$f" .scope)"
    echo "   ▸ ${stem#*-} (lane-scoped: once, in the source tree)"
    (cd "$src/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/$stem.wd")" && bash -e "$scratch/steps/$stem.sh") \
      > "$scratch/$stem.log" 2>&1 || { echo "FAIL: the lane's ${stem#*-} step" >&2; tail -30 "$scratch/$stem.log" >&2; exit 1; }
  done
  python3 "$here/lib/stage-job.py" "$src" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
  echo "   staged: install scope lane — node_modules → the source tree's"
else
  python3 "$here/lib/stage-job.py" "$src" "$work"
  [ ! -e "$work/node_modules" ] || { echo "FAIL: the staged tree carries node_modules" >&2; exit 1; }
  echo "   staged: install scope job — the job installs inside its own tree"
fi
for out in dist .wrangler .turbo; do
  [ ! -e "$work/$path/$out" ] || { echo "FAIL: the staged tree carries $path/$out — build output a fresh job does not have" >&2; exit 1; }
done
[ ! -e "$work/$path/.dev.vars" ] || { echo "FAIL: the staged tree carries .dev.vars" >&2; exit 1; }

for f in "$scratch"/steps/[0-9][0-9]-*.sh; do
  stem="$(basename "$f" .sh)"; step="${stem#*-}"
  [ "$(cat "$scratch/steps/$stem.scope")" = lane ] && continue   # ran above, in the source tree
  echo "   ▸ $step"
  dir="$work/$path/$(cat "$scratch/steps/$stem.wd")"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`) and the runtime ids every step gets; the step runs in the
  # component's directory unless it names another.
  if ! (cd "$dir" && { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage ORUN_COMPONENT=recipes ORUN_JOB_ID="$(cat "$scratch/steps/jobid")" && \
        bash -e "$f") > "$scratch/$stem.log" 2>&1; then
    echo "FAIL: the stage lane's $step step" >&2; tail -40 "$scratch/$stem.log" >&2; exit 1
  fi
done
$lane_scoped || { [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ]; } \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
grep -q "env stage" "$scratch"/steps/*-deploy-dry-run.sh \
  || { echo "FAIL: the dry run does not target the stage environment" >&2; exit 1; }
grep -Eq "ENVIRONMENT.*\"stage\"" "$scratch"/*-deploy-dry-run.log \
  || { echo "FAIL: the stage dry run did not bind ENVIRONMENT=stage" >&2; tail -20 "$scratch"/*-deploy-dry-run.log >&2; exit 1; }
grep -q "MAINTENANCE_MODE" "$scratch"/*-deploy-dry-run.log \
  || { echo "FAIL: the stage dry run did not bind MAINTENANCE_MODE" >&2; exit 1; }
grep -q "RATE_LIMITER" "$scratch"/*-deploy-dry-run.log \
  || { echo "FAIL: the stage dry run did not bind the rate limiter" >&2; exit 1; }
echo "   the dry run binds ENVIRONMENT=stage, MAINTENANCE_MODE and RATE_LIMITER"

# ── 3. serve it as a fresh deploy has it, and smoke it as the deploy does ──
echo "── wrangler dev --env stage over the staged Worker (no secret set)"
start_dev "$work/$path" "$scratch/dev.log"
echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$work/$path/component.yaml")"
DEPLOYED_URL="$url" ORUN_ENVIRONMENT=stage bash -c "set -uo pipefail; $smoke" \
  || { echo "FAIL: the deploy's smoke refused the Worker" >&2; exit 1; }

echo "   ▸ every route the product promises"
python3 - "$url" "$values" <<'PY'
import html, json, re, sys, urllib.error, urllib.request
base, values = sys.argv[1], json.load(open(sys.argv[2]))
name, repo, org = values["productname"], values["reponame"], values["githuborg"]
problems = []
def bad(m): problems.append(m)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None
opener = urllib.request.build_opener(NoRedirect)
def get(path, headers=None):
    req = urllib.request.Request(base + path, headers=headers or {})
    try:
        with opener.open(req, timeout=30) as r:
            return r.status, r.headers, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode(errors="replace")

# THE ONE ONLY THE WORKER ANSWERS: workerd's Rate Limiting binding (the
# unit tests use a fake). 5 per 10 s per IP; the sixth is redirected.
codes = []
for _ in range(6):
    s, h, _b = get("/rate-limit-any-framework")
    codes.append((s, h.get("location", "")))
if [c for c, _ in codes[:5]] != [200] * 5 or codes[5][0] != 302 or \
        not codes[5][1].endswith("/rate-limit-any-framework/blocked.html"):
    bad(f"the rate limiter answered {codes} — want five 200s, then 302 to /blocked.html")
s, _, b = get("/rate-limit-any-framework/blocked.html")
if s != 200 or "Workers Rate Limiting" not in b:
    bad(f"/rate-limit-any-framework/blocked.html answered {s}")

# The index: the product's name, its source link, every recipe.
s, _, page = get("/")
if s != 200:
    bad(f"/ answered {s}")
h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
if not h1 or html.unescape(h1.group(1)).strip() != name:
    bad(f"the index's heading is {h1 and h1.group(1)!r}, not {name!r}")
title = re.search(r"<title>(.*?)</title>", page, re.S)
if not title or html.unescape(title.group(1)) != name:
    bad(f"the index's <title> is {title and title.group(1)!r}, not {name!r}")
if f'href="https://github.com/{org}/{repo}"' not in page:
    bad(f"the footer does not link the product's repository github.com/{org}/{repo}")
slugs = ["geolocation", "i18n", "basic-auth-password", "rate-limit-any-framework",
         "ab-testing-simple", "maintenance-page", "cookies", "add-header",
         "modify-request-header", "query-params-filter", "json-response",
         "user-agent-based-rendering", "redirects-bloom-filter"]
for slug in slugs:
    if f'href="/{slug}"' not in page:
        bad(f"the index does not list /{slug}")
    # Each recipe's own page answers, and no recipe answers with a server
    # error — basic auth's 503 is its setup page, checked below.
    s, _, _b = get(f"/{slug}")
    if s >= 500 and not (slug == "basic-auth-password" and s == 503):
        bad(f"/{slug} answered {s}")
if "Edge Middleware Recipes" in page or "edge-middleware-recipes" in page:
    bad("the index still carries the baseline's name")

s, _, b = get("/geolocation")
if s != 200 or "<h1>Geolocation</h1>" not in b or "Languages" not in b:
    bad(f"/geolocation answered {s} without the geolocation page (request.cf, rewritten to /geolocation/index)")
s, _, b = get("/i18n", {"Accept-Language": "fr"})
if s != 200 or "Bonjour!" not in b or "locale:  fr" not in b:
    bad(f"/i18n with Accept-Language: fr answered {s} without the French dictionary")
# BASIC AUTH, AS A FRESH DEPLOY HAS IT: no pair set, so a setup page — not
# a 500, not a challenge nobody can pass, and never the protected page.
for hdr in ({}, {"Authorization": "Basic dW5kZWZpbmVkOnVuZGVmaW5lZA=="}):
    s, h, b = get("/basic-auth-password", hdr)
    if s != 503 or "Incomplete Secrets Setup" not in b or "orun secrets set BASIC_AUTH_USER" not in b \
            or "Password-protected page demo" in b or h.get("www-authenticate"):
        bad(f"/basic-auth-password without its secrets answered {s} — want the 503 setup page")
s, h, b = get("/ab-testing-simple/home")
if s != 200 or "Home page variant" not in b or not re.search(r"bucket-home=[abc]; Path=/", h.get("set-cookie", "")):
    bad(f"/ab-testing-simple/home answered {s}, Set-Cookie {h.get('set-cookie')!r}")
s, h, b = get("/ab-testing-simple/marketing", {"Cookie": "bucket-marketing=original"})
if s != 200 or "the original marketing page" not in b or h.get("set-cookie"):
    bad(f"/ab-testing-simple/marketing with its bucket answered {s} (Set-Cookie {h.get('set-cookie')!r})")
s, _, b = get("/maintenance-page/big-promo")
if s != 200 or "Something big is coming" not in b:
    bad(f"/maintenance-page/big-promo with the flag off answered {s} without the promo")
s, _, b = get("/cookies")
if s != 200 or "You are not in beta." not in b:
    bad(f"/cookies answered {s} without the non-beta page")
s, _, b = get("/cookies", {"Cookie": "beta=true"})
if s != 200 or "You are currently in beta!" not in b:
    bad(f"/cookies with beta=true answered {s} without the beta page")
s, h, _b = get("/cookies/opt-in")
if s != 302 or "beta=true" not in h.get("set-cookie", ""):
    bad(f"/cookies/opt-in answered {s}, Set-Cookie {h.get('set-cookie')!r}")
s, h, _b = get("/add-header")
if s != 200 or h.get("x-modified-edge") != "true":
    bad(f"/add-header answered {s} with x-modified-edge {h.get('x-modified-edge')!r}")
s, _, b = get("/modify-request-header", {"x-from-client": "secret", "User-Agent": "curl/8"})
for want in ("x-hello-from-middleware1: </strong>hello", "x-hello-from-middleware2: </strong>world!",
             "user-agent: </strong>New User Agent overriden by middleware!", "x-from-client: </strong>(deleted)"):
    if want not in b:
        bad(f"/modify-request-header does not show {want!r}")
s, h, _b = get("/query-params-filter?a=b&allowed=test")
if s != 307 or not h.get("location", "").endswith("/query-params-filter?allowed=test"):
    bad(f"/query-params-filter?a=b&allowed=test answered {s} → {h.get('location')!r}")
s, h, b = get("/json-response")
if s != 200 or not h.get("content-type", "").startswith("application/json") or json.loads(b) != {"message": "hello world!"}:
    bad(f"/json-response answered {s} {h.get('content-type')!r} {b[:60]!r}")
s, _, b = get("/user-agent-based-rendering", {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"})
if s != 200 or "loaded on a <b>mobile</b> device" not in b:
    bad(f"/user-agent-based-rendering on an iPhone answered {s} without the mobile page")
s, _, b = get("/user-agent-based-rendering", {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"})
if s != 200 or "loaded on a <b>desktop</b> device" not in b:
    bad(f"/user-agent-based-rendering on a Mac answered {s} without the desktop page")
s, h, _b = get("/redirects-bloom-filter/blog/should-redirect-to-google")
if s != 307 or h.get("location") != "https://www.google.com":
    bad(f"a Bloom-filter hit answered {s} → {h.get('location')!r}")
s, _, b = get("/redirects-bloom-filter/blog/should-render-basic-blog-post")
if s != 200 or "Blog Post" not in b:
    bad(f"a Bloom-filter miss answered {s} without the blog post")
s, _, _b = get("/no-such-recipe")
if s != 404:
    bad(f"/no-such-recipe answered {s}, not 404")
done = "the rate limiter (workerd's binding), the index, all 13 recipes as a fresh deploy serves them, a 404"

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {done}")
PY
stop_dev

# ── 4. serve it as its owner configures it ─────────────────────────────────
echo "── wrangler dev --env stage, with the basic-auth pair and the maintenance flag set"
start_dev "$work/$path" "$scratch/dev-owner.log" \
  --var BASIC_AUTH_USER:4dmin --var BASIC_AUTH_PASSWORD:testpwd123 --var MAINTENANCE_MODE:true
python3 - "$url" <<'PY' || exit 1
import sys, urllib.error, urllib.request
base = sys.argv[1]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None
opener = urllib.request.build_opener(NoRedirect)
def get(path, headers=None):
    req = urllib.request.Request(base + path, headers=headers or {})
    try:
        with opener.open(req, timeout=30) as r:
            return r.status, r.headers, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode(errors="replace")
problems = []
s, h, b = get("/basic-auth-password")
if s != 401 or h.get("www-authenticate") != 'Basic realm="Secure Area"' or b != "Auth Required.":
    problems.append(f"/basic-auth-password with its secrets set and no header answered {s} {h.get('www-authenticate')!r}")
s, _, _b = get("/basic-auth-password", {"Authorization": "Basic NGRtaW46bm9wZQ=="})
if s != 401:
    problems.append(f"/basic-auth-password with a wrong pair answered {s}, not 401")
s, _, b = get("/basic-auth-password", {"Authorization": "Basic NGRtaW46dGVzdHB3ZDEyMw=="})
if s != 200 or "Password-protected page demo" not in b:
    problems.append(f"/basic-auth-password with the right pair answered {s} without the protected page")
s, _, b = get("/maintenance-page/big-promo")
if s != 200 or "Under Maintenance" not in b:
    problems.append(f"/maintenance-page/big-promo with the flag on answered {s} without the maintenance page")
for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
if problems:
    sys.exit(1)
print("   basic auth's challenge, a wrong pair and the right one; the maintenance page with its flag on")
PY
stop_dev

echo "e2e.test.sh: ok"
