# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`payload-website/`](./payload-website/) | **PW** | In progress (PW0) | Vercel's Payload Website Starter — Payload CMS and its site — on Cloudflare Workers, D1 and R2, and an Orun baseline that instantiates it (PW2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
