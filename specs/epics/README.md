# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`edge-middleware-recipes/`](./edge-middleware-recipes/) | **EM** | Draft | Vercel's Edge Middleware examples, each ported as a Cloudflare Worker recipe with its behaviour intact |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
