#!/usr/bin/env bash
# The phases in `repo-blueprint.yaml` must be the phases the bootstrap runs,
# placing what they are meant to place, saying what they are, and naming only
# what the engine can resolve.
#
# The partition below is the bootstrap's order, written down a second time on
# purpose: the product is ONE landing (cirrus-baseline's v22 shape) — every
# module placed by `01-product`, the phase that deploys — and the deployment
# record (`02-docs`, hooks only) cannot be written before the product is live.
# A module that drifts into another phase, or a hook that moves, fails at
# landing time, live, with nothing in this repository having looked wrong.
# Moving one is a deliberate change, argued in the diff that edits both places.
#
# And the shape that keeps a bootstrap fast (orun >= v2.88.0, turso-starter
# baseline-v8's): the run-level task set-up runs in the background, each
# phase finds its task just before its landing, each landing checks its
# commit here (`checks: local`), and the convergence watch reads every few
# seconds.
#
# Adapted from sourceplane/cirrus-baseline's testing/phases.test.sh: the
# narration rules and the hook-only rule are Cirrus's, unchanged.
#
# bash + python3 + PyYAML. No network, no fakes, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── repo-blueprint.yaml phases against what the bootstrap runs"
python3 - "$root" <<'PY'
import pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the phase contract test (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []
def bad(m): problems.append(m)

bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
phases = bp.get("phases") or []
if not phases:
    sys.exit("repo-blueprint.yaml declares no phases — this check has gone blind")

PARTITION = {
    "01-product": ["ai-deployment", "ai-operations", "discovery-roots", "github-workflows",
                   "rebrand-values", "recipes", "recipes-tests", "root-gitignore",
                   "root-intent", "root-package-json",
                   "root-pnpm-lock", "root-pnpm-workspace", "root-readme", "root-turbo",
                   "tooling-eslint", "tooling-tsconfig", "tooling-wire", "vscode"],
    "02-docs": [],
}
HOOK_ONLY = {"02-docs"}
# The phases that DEPLOY, and so must give a re-run something to land.
DEPLOYS = {"01-product"}

# THE HOOKS, IN ORDER (cirrus-baseline v22's 01-product, without the hooks
# this product has no use for: no console artifact, no infra and so no
# wiring-secret await). The order is load-bearing — the marker before the
# first stage so it is branded and landed; git before the rebrand, which reads
# `git ls-files`; the re-tenant, work-tree strip and deferrals before the
# re-stage and the residue sweep; the repository and its link before the
# reconcile, which mints for the linked project; the task, then the one
# landing; the watch before the probe.
#   No phase has a `pre` hook: the task is found in `post`, just before the
# landing, so that everything before it runs beside the background task
# set-up. The brokered keys are one `secrets` reconcile (checked below).
# 02-docs awaits nothing: its render probes as it writes, and its landing
# redeploys nothing.
HOOK_ORDER = {
    "01-product": {
        "pre": [],
        "post": ["retouch", "git-init", "git-stage", "rebrand", "orun-workspace",
                 "work-tree", "promotion", "dev-lanes", "git-restage", "rebrand-verify",
                 "repo", "link", "secrets", "task", "land"],
        "await": ["converge", "verify"],
    },
    "02-docs": {
        "pre": [],
        "post": ["promotion", "dev-lanes", "render", "task", "land"],
        "await": [],
    },
}
# What each `run:` hook runs, by id — the script and the flag, so a hook that
# keeps its id and changes its work is caught too.
HOOK_RUNS = {
    ("01-product", "retouch"): ("tooling/bootstrap/retouch.mjs", "--phase"),
    ("01-product", "rebrand"): ("tooling/rebrand/rebrand.mjs", "--allow-dirty"),
    ("01-product", "work-tree"): ("tooling/bootstrap/work-tree.mjs", "--strip"),
    ("01-product", "promotion"): ("tooling/bootstrap/promotion.mjs", "--defer"),
    ("01-product", "dev-lanes"): ("tooling/bootstrap/dev-lanes.mjs", "--defer"),
    ("01-product", "rebrand-verify"): ("tooling/rebrand/rebrand.mjs", "--verify"),
    ("02-docs", "promotion"): ("tooling/bootstrap/promotion.mjs", "--restore"),
    ("02-docs", "dev-lanes"): ("tooling/bootstrap/dev-lanes.mjs", "--restore"),
    ("02-docs", "render"): ("hooks/render-deployment-docs.sh", ""),
}
HOOK_USES = {
    ("01-product", "task"): "orun.task/ensure@v1",
    ("01-product", "repo"): "orun.repo/ensure@v1",
    ("01-product", "secrets"): "orun.integrations/reconcile@v1",
    ("01-product", "land"): "orun.pr/land@v1",
    ("01-product", "converge"): "orun.run/watch@v1",
    ("01-product", "verify"): "orun.http/probe@v1",
    ("02-docs", "task"): "orun.task/ensure@v1",
    ("02-docs", "land"): "orun.pr/land@v1",
}

by_name = {p["name"]: p for p in phases}
names = [p["name"] for p in phases]

# ── the order IS the execution order ──────────────────────────────────────
if names != sorted(names):
    bad(f"phases are not in execution order: {names}. The numbered name IS the "
        f"order; a phase out of sequence is a barrier in the wrong place.")
if names != list(PARTITION):
    bad(f"phases are {names}; the bootstrap runs {list(PARTITION)}")

# ── the partition has not drifted ─────────────────────────────────────────
for name, want in PARTITION.items():
    if name not in by_name:
        continue
    now = sorted(by_name[name].get("modules") or [])
    if now != sorted(want):
        bad(f"phase {name} no longer places what it placed: gained "
            f"{sorted(set(now) - set(want)) or '[]'}, lost {sorted(set(want) - set(now)) or '[]'}")
declared = {m["name"] for m in bp.get("modules") or []}
placed = {m for p in phases for m in (p.get("modules") or [])}
for m in sorted(declared - placed):
    bad(f"module {m} is declared and no phase places it")
for name in HOOK_ONLY:
    if by_name.get(name, {}).get("modules"):
        bad(f"phase {name} places modules — it is declared as hooks only")

# ── nothing may GATE on a phase the tree cannot answer for ────────────────
# A hook-only phase places no files, so orun derives it as `unknown`, and
# `requires.phases` fails closed on `unknown`: a requirement naming one can
# never be satisfied.
for p in phases:
    for need in ((p.get("requires") or {}).get("phases") or []):
        if need in HOOK_ONLY:
            bad(f"phase {p['name']} requires {need}, which places no files — require "
                f"its predecessor instead")
        if need not in by_name or names.index(need) >= names.index(p["name"]):
            bad(f"phase {p['name']} requires {need}, which does not run before it")

# ── every phase says what it is and what to budget ────────────────────────
for p in phases:
    for field in ("title", "expectedMinutes"):
        if not p.get(field):
            bad(f"phase {p['name']} declares no {field} — an operator reads both")
    if not (p.get("hooks") or {}):
        bad(f"phase {p['name']} declares no hooks — a phase that only places files "
            f"still has to land them")

def hooks_of(p):
    h = p.get("hooks") or {}
    if isinstance(h, list):
        return list(h)
    return [x for slot in ("pre", "post", "await") for x in (h.get(slot) or [])]

run_hooks = list((bp.get("hooks") or {}).get("preInstantiate") or [])

# ── every phase lands, and every landing is bound to its task ─────────────
for p in phases:
    ids = [h.get("id") for h in hooks_of(p)]
    lands = [h for h in hooks_of(p) if (h.get("uses") or "").startswith("orun.pr/land@")]
    if len(lands) != 1:
        bad(f"phase {p['name']} has {len(lands)} landing(s); a phase is ONE pull request")
        continue
    w = lands[0].get("with") or {}
    if w.get("task") != "{{ .phase.hooks.task.outputs.key }}":
        bad(f"phase {p['name']} lands without binding the PR to its task key")
    if "task" not in ids or ids.index("task") > ids.index(lands[0].get("id")):
        bad(f"phase {p['name']} must ensure its task before it lands")
    if p["name"] in DEPLOYS:
        if not any("retouch.mjs" in " ".join(h.get("run") or []) for h in hooks_of(p)):
            bad(f"phase {p['name']} deploys and has no retouch hook — a re-run after a "
                f"failed convergence would land an empty diff and redeploy nothing")
        awaits = (p.get("hooks") or {}).get("await") or []
        watch = [h for h in awaits if (h.get("uses") or "").startswith("orun.run/watch@")]
        if not watch or (watch[0].get("with") or {}).get("sha") != "{{ .phase.hooks.land.outputs.mergeSha }}":
            bad(f"phase {p['name']} deploys and does not watch the convergence of the "
                f"commit it merged (orun.run/watch@v1 with sha: mergeSha)")

# ── every phase's task is one the run-level list opens, in the same order ─
def task_names(hooks):
    return [(h.get("with") or {}).get("name") for h in hooks
            if (h.get("uses") or "").startswith("orun.task/ensure@")
            and (h.get("with") or {}).get("kind") == "task"]
opened = task_names(run_hooks)
per_phase = [n for p in phases for n in task_names(hooks_of(p))]
if opened != per_phase:
    bad(f"the run-level list opens tasks {opened}; the phases ensure {per_phase} — "
        f"a task is found by its title, so the two must be the same words")
milestones = [(h.get("with") or {}).get("name") for h in run_hooks
              if (h.get("with") or {}).get("kind") == "milestone"]
if milestones != names:
    bad(f"the run-level list opens milestones {milestones}; the phases are {names}")

# ── every contract a hook names exists, beside the blueprint ──────────────
for h in run_hooks + [x for p in phases for x in hooks_of(p)]:
    rel = (h.get("with") or {}).get("contract")
    if rel and not (root / rel).exists():
        bad(f"hook {h.get('id')} names contract {rel}, which does not exist")
    if rel and not rel.startswith(".baseline/tasks/"):
        bad(f"hook {h.get('id')} names contract {rel} outside .baseline/tasks/ — "
            f"`tasks/` is this repository's own work tree, where an unkeyed "
            f"contract is an error")
for p in phases:
    for h in hooks_of(p):
        argv = " ".join(h.get("run") or [])
        for ref in re.findall(r"\{\{ \.baseline\.dir \}\}/(\S+?)(?:\"|'|\s|$)", argv + " "):
            if not (root / ref).exists():
                bad(f"phase {p['name']} hook {h.get('id')} runs {ref}, which this "
                    f"repository does not have")

# ── the hooks, in the order the bootstrap runs them ───────────────────────
for name, slots in HOOK_ORDER.items():
    p = by_name.get(name)
    if p is None:
        continue
    h = p.get("hooks") or {}
    for slot, want in slots.items():
        now = [x.get("id") for x in (h.get(slot) or [])]
        if now != want:
            why = (" — a task found in `pre` waits for the background task set-up before "
                   "the phase has done anything") if slot == "pre" else ""
            bad(f"phase {name} {slot} hooks are {now}; the bootstrap runs {want}{why}")
    for x in [y for slot in ("pre", "post", "await") for y in (h.get(slot) or [])]:
        hid = x.get("id")
        if (name, hid) in HOOK_RUNS:
            script, flag = HOOK_RUNS[(name, hid)]
            argv = " ".join(x.get("run") or [])
            if script not in argv or (flag and flag not in argv):
                bad(f"phase {name} hook {hid} runs `{argv}` — it must run {script} {flag}".rstrip())
        if (name, hid) in HOOK_USES and x.get("uses") != HOOK_USES[(name, hid)]:
            bad(f"phase {name} hook {hid} uses {x.get('uses')!r}, not {HOOK_USES[(name, hid)]}")

# The brokered keys are minted where the product deploys: in 01-product, after
# the link and before the landing, in ONE `secrets` reconcile per provider
# (orun >= v2.87.0): each key under its own scope template, the connections and
# the existing secrets read once per hook, the missing keys created side by
# side. A reconcile reads one connection, so two providers would be two hooks
# (`secrets-<provider>`); two hooks whose other parameters are the same are one
# hook written twice.
reconciles = [(p, x) for p in phases for x in hooks_of(p)
              if (x.get("uses") or "").startswith("orun.integrations/reconcile@")]
shared = {}
for p, x in reconciles:
    w = x.get("with") or {}
    want = "secrets" if len(reconciles) == 1 else f"secrets-{w.get('provider')}"
    if x.get("id") != want:
        bad(f"reconcile hook {x.get('id')} mints from {w.get('provider')}; name it {want}")
    if p["name"] not in DEPLOYS:
        bad(f"phase {p['name']} reconciles {[i.get('key') for i in w.get('secrets') or []]} — the "
            f"brokered keys belong to the phase that deploys")
    if "keys" in w or "template" in w or not w.get("secrets"):
        bad(f"hook {x.get('id')} does not use the `secrets: [{{key, template}}]` form — one "
            f"template per hook reads the connections and the secrets once per key")
    for item in w.get("secrets") or []:
        if not item.get("key") or not item.get("template"):
            bad(f"hook {x.get('id')} mints {item} — every key names its own scope template")
    same = tuple(sorted((k, str(v)) for k, v in w.items() if k != "secrets"))
    if same in shared:
        bad(f"hooks {shared[same]} and {x.get('id')} take the same parameters {dict(same)} — "
            f"merge them into one `secrets` list")
    shared.setdefault(same, x.get("id"))

# No infra component, no wiring secret to wait for: an `orun.secrets/exists@v1`
# await exists exactly when the tree has a component under infra/.
has_infra = any(m.get("from", "").startswith("infra/") for m in bp.get("modules") or [])
for p in phases:
    waits = [x for x in ((p.get("hooks") or {}).get("await") or [])
             if (x.get("uses") or "").startswith("orun.secrets/exists@")]
    if waits and not has_infra:
        bad(f"phase {p['name']} waits on {waits[0].get('with', {}).get('keys')} and no "
            f"infra component publishes any")
    if has_infra and p["name"] in DEPLOYS and not waits:
        bad(f"phase {p['name']} deploys infra and does not check its WIRING_* secrets")

# ── THE FAST SHAPE (orun >= v2.88.0) ──────────────────────────────────────
# The run-level list is the task set-up, all of it in the background: the
# first phase's provider check, placement, rebrand, repository and secrets
# run while it opens the epic, the milestones and the tasks.
for h in run_hooks:
    if not h.get("background"):
        bad(f"hooks.preInstantiate {h.get('id')} is not `background: true` — the first phase "
            f"waits for it before doing anything, though nothing before its landing reads it")
# A `pre` hook on the task plane would wait for that background at once,
# before the phase had placed a file — the old order, whatever its id.
for p in phases:
    for h in ((p.get("hooks") or {}).get("pre") or []):
        if (h.get("uses") or "").startswith(("orun.task/", "orun.pr/")):
            bad(f"phase {p['name']}'s pre hook {h.get('id')} uses {h['uses']}, which waits for the "
                f"background task set-up — find the task in `post`, just before the landing")
# Every landing checks its commit here and merges, instead of waiting ~25 s
# for a runner to plan the tree this box just wrote.
for p in phases:
    for h in hooks_of(p):
        if (h.get("uses") or "").startswith("orun.pr/land@") and (h.get("with") or {}).get("checks") != "local":
            bad(f"phase {p['name']} lands with checks {(h.get('with') or {}).get('checks', 'ci')!r}, "
                f"not 'local' — it waits for a runner to plan a tree that is here")
# The convergence watch reads every few seconds, not the action's default 40.
for p in phases:
    for h in ((p.get("hooks") or {}).get("await") or []):
        if (h.get("uses") or "").startswith("orun.run/watch@"):
            every = (h.get("with") or {}).get("pollSeconds")
            if not isinstance(every, int) or every > 10:
                bad(f"phase {p['name']} watches its convergence every {every or 40} s; at most 10 — "
                    f"the build goes on that much after the run is green")
# The shipped lockfile is installed frozen by the lanes and by the baseline's
# e2e tier; a hook re-resolving it is network for nothing.
for p in phases:
    for h in hooks_of(p):
        if "--lockfile-only" in (h.get("run") or []):
            bad(f"phase {p['name']} hook {h.get('id')} re-resolves the lockfile the baseline ships")

# The deploying phase probes the Worker the card's verify URL names.
card = yaml.safe_load((root / "blueprint.yaml").read_text())
card_urls = ((card.get("spec") or {}).get("verify") or {}).get("urls") or []
for p in phases:
    for x in ((p.get("hooks") or {}).get("await") or []):
        if (x.get("uses") or "").startswith("orun.http/probe@"):
            got = (x.get("with") or {}).get("urls") or []
            want = sorted(u.replace("{reponame}", "{{ .inputs.reponame }}")
                           .replace("{subdomain}", "{{ .inputs.subdomain }}")
                           .replace("{env}", e) for u in card_urls for e in ("stage", "prod"))
            if sorted(got) != want:
                bad(f"phase {p['name']} probes {got}; the card verifies {want}")

# ── every phase has a documentation page, and every page a phase ──────────
docs_dir = root / "docs" / "phases"
pages = {f.stem for f in docs_dir.glob("*.md")} - {"README"}
for n in names:
    if n not in pages:
        bad(f"phase {n} has no page at docs/phases/{n}.md")
for page in sorted(pages - set(names)):
    bad(f"docs/phases/{page}.md documents a phase repo-blueprint.yaml does not declare")

# ── narration: authored here, printed from state (Cirrus's rules) ─────────
META_AT = {
    "start": {"files", "expectedMinutes"},
    "await": {"files", "expectedMinutes"},
    "failed": {"files", "expectedMinutes"},
    "done": {"files", "expectedMinutes", "elapsed", "next"},
}
STATE_WORDS = {"done", "failed", "complete", "completed", "succeeded", "skipped"}
PHASE_KEYS = {"name", "title"}
input_keys = set((bp.get("inputs") or {}).keys())

ws_input = (bp.get("inputs") or {}).get("orunWorkspace") or {}
if ws_input.get("from") != "workspace":
    bad("inputs.orunWorkspace must declare `from: workspace` — a console build has no other way to say it")

def strip_expressions(line):
    return re.sub(r"\{\{.*?\}\}", "", line, flags=re.S)

def refs(line):
    found = []
    for expr in re.findall(r"\{\{(.*?)\}\}", line, re.S):
        found += re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expr)
    return found

def check_line(where, line, slot, hook_ids):
    prose = strip_expressions(line).lower()
    for w in STATE_WORDS:
        if re.search(rf"\b{w}\b", prose):
            bad(f"{where} asserts {w!r} — `state` is the truth and narration is the "
                f"caption. Describe the world, not the run.")
    for ref in refs(line):
        parts = ref.split(".")
        head = parts[0]
        if head == "phase":
            if len(parts) != 2 or parts[1] not in PHASE_KEYS:
                bad(f"{where} names .{ref}; a phase carries {sorted(PHASE_KEYS)}")
        elif head == "inputs":
            if len(parts) != 2 or parts[1] not in input_keys:
                bad(f"{where} names .{ref}, which is not a declared input")
        elif head == "meta":
            allowed = META_AT.get(slot, META_AT["start"])
            if len(parts) != 2 or parts[1] not in allowed:
                bad(f"{where} names .{ref}; the {slot} event carries {sorted(allowed)}")
        elif head == "hooks":
            if len(parts) < 2 or parts[1] not in hook_ids:
                bad(f"{where} names .{ref}; this phase has no such hook")
        else:
            bad(f"{where} names .{ref}; narration may reference phase, inputs, meta and hooks")

for p in phases:
    n = p.get("narrate") or {}
    ids = {h.get("id") for h in hooks_of(p)}
    awaits = bool((p.get("hooks") or {}).get("await"))
    for slot in ("start", "await", "done", "failed"):
        line = n.get(slot)
        if slot == "await" and not awaits:
            # A phase that waits on nothing never says its await line.
            if line:
                bad(f"phase {p['name']} declares narrate.await and has no await hooks — "
                    f"nobody would ever read it")
            continue
        if not line:
            bad(f"phase {p['name']} declares no narrate.{slot}")
            continue
        check_line(f"phase {p['name']} narrate.{slot}", line, slot, ids)
    for h in ((p.get("hooks") or {}).get("await") or []):
        line = h.get("narrate")
        if not line:
            bad(f"phase {p['name']} await hook {h.get('id')} declares no narrate — a "
                f"wait with no words reads as a stalled build")
            continue
        check_line(f"phase {p['name']} hook {h.get('id')} narrate", line, "done", ids)
    for slot in ("pre", "post"):
        for h in ((p.get("hooks") or {}).get(slot) or []):
            if h.get("narrate"):
                check_line(f"phase {p['name']} hook {h.get('id')} narrate", h["narrate"], "start", ids)

# ── what a baseline of this shape never grows back ────────────────────────
if (root / "flows").exists():
    bad("flows/ exists — the bootstrap is the blueprint; every mechanism is a typed orun action")

if problems:
    print("FAIL: the blueprint's phases and the bootstrap disagree:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

placed_n = sum(len(p.get("modules") or []) for p in phases)
narrated = sum(len(p.get("narrate") or {}) for p in phases)
narrated += sum(1 for p in phases for h in hooks_of(p) if h.get("narrate"))
print(f"   {len(phases)} phases, {placed_n} modules, {len(HOOK_ONLY)} hook-only — in execution order")
print(f"   every hook in the order the bootstrap runs it; {', '.join(sorted(DEPLOYS))} deploys and probes the card's URLs")
print(f"   the fast shape: the task set-up in the background, no `pre` hook, every landing checks: local, the watch every few seconds")
print(f"   {narrated} authored narration lines, every reference resolving")
PY

echo "phases.test.sh: ok"
