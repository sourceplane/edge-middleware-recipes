#!/usr/bin/env bash
# THE LEAK GATE — what a product carries, and what stays in the factory.
#
# A product built from this baseline is somebody's product, not a copy of
# this repository. It gets the product: the Worker, its tests, its CI, its
# tooling, its README and its two context pages. It does NOT get the factory:
# the blueprints, the bootstrap and rebrand tooling, the test gates, the task
# contracts and identity under `.baseline/`, this repository's own epic and
# task tree, BOOTSTRAP.md — nor `tooling/migrations`, a D1 manifest check this
# product has no database for.
#
# This asks orun to DERIVE the placement — every file every phase would write
# — and gates that set: its paths, and the CONTENT of every file in it, which
# must not send a reader to a factory path (`repo-blueprint`, `testing/`,
# `specs/`, `tasks/`, `.baseline/`) that the product does not have.
# Derivation runs no hooks, contacts nothing and writes nothing.
# testing/placement.test.sh gates the same rules over a tree that is actually
# placed and branded.
#
# Needs: orun + python3. No network, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v orun >/dev/null || { echo "leak.test.sh needs orun on PATH" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "── deriving what every phase would place"
sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$here/fixtures/acme.json" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)
orun new --blueprint "$root/repo-blueprint.yaml" --status --json \
  --out "$scratch/empty" "${sets[@]}" > "$scratch/status.json"

python3 - "$scratch/status.json" "$root" <<'PY'
import json, pathlib, re, sys

status = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
problems = []
def bad(m): problems.append(m)

# Against an empty output directory every file a phase places is "missing", so
# the union of those lists IS the site's file set.
placed = sorted({f for ph in status["phases"] for f in (ph.get("missing") or [])})
if len(placed) < 50:
    sys.exit(f"only {len(placed)} files derived — the tree is not a product")

# ── the context pack, exactly ─────────────────────────────────────────────
ALLOWED_AI = {"ai/context/deployment.md", "ai/context/operations.md"}
shipped_ai = {p for p in placed if p.startswith("ai/")}
for extra in sorted(shipped_ai - ALLOWED_AI):
    bad(f"{extra} ships to the product and is this repository's own state")
for missing in sorted(ALLOWED_AI - shipped_ai):
    bad(f"{missing} is declared a product file and would not ship")

# ── the factory never ships ───────────────────────────────────────────────
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", "tooling/migrations/",
         ".github/workflows/baseline.yml", ".github/workflows/tag.yml", "BOOTSTRAP.md",
         "repo-blueprint.yaml", "blueprint.yaml", "flows/", "agents/")
for p in placed:
    for never in NEVER:
        if p == never or p.startswith(never):
            bad(f"{p} would ship — it is the factory, not the product")

# ── nothing local and nothing built ───────────────────────────────────────
# `.dev.vars.example` is the one `.dev.vars*` that ships: the README tells an
# owner to copy it, and it holds the upstream's demo pair, never a real one.
LOCAL = re.compile(r"(^|/)(\.env(\.[^/]*\.local|\.local)?|\.dev\.vars(\.(?!example$)[^/]*)?|"
                   r"node_modules|\.wrangler|\.turbo|\.orun|dist|[^/]*\.tsbuildinfo)(/|$)")
for p in placed:
    if LOCAL.search(p):
        bad(f"{p} would ship — a local or built file of whoever ran the bootstrap")

# ── the product's README, not this repository's ───────────────────────────
if "README.md" not in placed:
    bad("README.md would not ship")
for must in (".github/workflows/ci.yml", ".github/workflows/checks.yml",
             "apps/recipes/component.yaml", "apps/recipes/src/site.ts",
             "apps/recipes/wrangler.jsonc", "apps/recipes/.dev.vars.example",
             "tests/recipes/component.yaml", "tests/recipes/src/site.test.ts",
             ".rebrand/values.json", "infra/.gitkeep", "packages/.gitkeep",
             "pnpm-lock.yaml", "tooling/wire/render.mjs"):
    if must not in placed:
        bad(f"{must} would not ship, and a product needs it")

# ── PROVENANCE, which rebrand has no rule for ─────────────────────────────
# Not a search for this baseline's name: the rebrand rewrites that, and this
# gate reads the sources before it runs. What the rebrand cannot rewrite is a
# sentence about where the product CAME FROM, or one about being a baseline.
PROVENANCE = re.compile(
    r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|\bthis baseline\b"
    r"|BOOTSTRAP\.md|repo-blueprint|specs/epics|\.baseline/",
    re.I,
)
SOURCES = {"README.md": ".baseline/product/README.md",
           "ai/context/operations.md": "ai/context/operations.md",
           "ai/context/deployment.md": "ai/context/deployment.md"}
for shipped, src in SOURCES.items():
    for n, line in enumerate((root / src).read_text(errors="replace").splitlines(), 1):
        if PROVENANCE.search(line):
            bad(f"{shipped} (from {src}:{n}) tells the product about the factory: {line.strip()[:80]}")

# ── NO SHIPPED FILE POINTS AT THE FACTORY ─────────────────────────────────
# Every file the product gets, read from the source it is placed from: a
# comment that says "see testing/e2e.test.sh" or "specs/epics/…/design.md"
# sends the product's reader to a path that is not in their repository. The
# templated files carry inputs only. intent.yaml is read as 01-product leaves
# it — its `work:` block, which names `specs/` and `tasks/`, is the baseline's
# own and the work-tree hook strips it (the strip is run, not assumed).
FACTORY_PATH = re.compile(r"repo-blueprint|BOOTSTRAP\.md|(?<![\w.@/-])\.?baseline/|"
                          r"(?<![\w.@-])(testing|specs|tasks|docs/phases)/")
TEMPLATED = {".rebrand/values.json", "apps/.gitkeep", "infra/.gitkeep",
             "packages/.gitkeep", "tests/.gitkeep"}
import subprocess, tempfile, shutil
def source_of(p):
    return ".baseline/product/README.md" if p == "README.md" else p
scanned = 0
for p in placed:
    if p in TEMPLATED:
        continue
    src = root / source_of(p)
    try:
        text = src.read_text(errors="replace")
    except (FileNotFoundError, IsADirectoryError):
        bad(f"{p} is derived but {source_of(p)} is not in this repository")
        continue
    if p == "intent.yaml":
        with tempfile.TemporaryDirectory() as d:
            tmp = pathlib.Path(d) / "intent.yaml"
            shutil.copy(src, tmp)
            subprocess.run(["node", str(root / "tooling/bootstrap/work-tree.mjs"), "--strip",
                            "--file", str(tmp)], check=True, capture_output=True)
            text = tmp.read_text()
    scanned += 1
    for n, line in enumerate(text.splitlines(), 1):
        m = FACTORY_PATH.search(line)
        if m:
            bad(f"{p}:{n} names {m.group(0)!r}, which the product does not have: {line.strip()[:80]}")

if problems:
    print("FAIL: the product would carry the baseline:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(placed)} files derived across every phase")
print(f"   ai/context is exactly {len(ALLOWED_AI)} declared file(s); none of the "
      f"{len(NEVER)} factory paths; nothing local or built; no provenance prose")
print(f"   {scanned} shipped files read: none points at a factory path")
PY

echo "leak.test.sh: ok"
