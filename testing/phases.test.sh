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
# reconcile, which mints for the linked project, and all of it before the one
# landing; the watch before the probe.
#   `secret-*` stands for the reconcile hooks, one per brokered key, in a run.
HOOK_ORDER = {
    "01-product": {
        "pre": ["task"],
        "post": ["retouch", "git-init", "git-stage", "rebrand", "orun-workspace",
                 "work-tree", "promotion", "dev-lanes", "git-restage", "rebrand-verify",
                 "pnpm-lockfile", "repo", "link", "secret-*", "land"],
        "await": ["converge", "verify"],
    },
    "02-docs": {
        "pre": ["task"],
        "post": ["promotion", "dev-lanes", "render", "land"],
        "await": ["verify"],
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
    ("01-product", "pnpm-lockfile"): ("pnpm", "--lockfile-only"),
    ("02-docs", "promotion"): ("tooling/bootstrap/promotion.mjs", "--restore"),
    ("02-docs", "dev-lanes"): ("tooling/bootstrap/dev-lanes.mjs", "--restore"),
    ("02-docs", "render"): ("hooks/render-deployment-docs.sh", ""),
}
HOOK_USES = {
    ("01-product", "task"): "orun.task/ensure@v1",
    ("01-product", "repo"): "orun.repo/ensure@v1",
    ("01-product", "land"): "orun.pr/land@v1",
    ("01-product", "converge"): "orun.run/watch@v1",
    ("01-product", "verify"): "orun.http/probe@v1",
    ("02-docs", "task"): "orun.task/ensure@v1",
    ("02-docs", "land"): "orun.pr/land@v1",
    ("02-docs", "verify"): "orun.http/probe@v1",
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
def collapse(ids):
    out = []
    for i in ids:
        i = "secret-*" if (i or "").startswith("secret-") else i
        if not out or out[-1] != i:
            out.append(i)
    return out

for name, slots in HOOK_ORDER.items():
    p = by_name.get(name)
    if p is None:
        continue
    h = p.get("hooks") or {}
    for slot, want in slots.items():
        now = collapse([x.get("id") for x in (h.get(slot) or [])])
        if now != want:
            bad(f"phase {name} {slot} hooks are {now}; the bootstrap runs {want}")
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
# the link and before the landing, one reconcile per scope template.
for p in phases:
    for x in hooks_of(p):
        if (x.get("uses") or "").startswith("orun.integrations/reconcile@"):
            if p["name"] not in DEPLOYS:
                bad(f"phase {p['name']} reconciles {x.get('with', {}).get('keys')} — the "
                    f"brokered keys belong to the phase that deploys")
            if len((x.get("with") or {}).get("keys") or []) != 1:
                bad(f"hook {x.get('id')} mints {x.get('with', {}).get('keys')} — one key per "
                    f"reconcile, so each key names its own scope template")

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
    for slot in ("start", "await", "done", "failed"):
        line = n.get(slot)
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
print(f"   {narrated} authored narration lines, every reference resolving")
PY

echo "phases.test.sh: ok"
