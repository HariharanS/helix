# workspaces AGENTS Guide

This directory is the canonical home for workspace-scoped feature artifacts.

## Canonical Structure

```text
workspaces/{name}/
├── workspace.yml
├── refined-intent.md
├── prd.md or prd/
├── tech-design.md or tech-design/
├── task-boards/
├── execution-plans/
├── decisions/
└── context-bundle-*.md
```

Current target-state naming uses `workspace.yml`. Older combined-repo examples may still refer to legacy `workspace.yaml`.

## Source Of Truth Rules

- `workspace.yml` is the entry point for participating repos, workspace status, and artifact entry paths
- `execution-plans/` is the machine-readable source of truth for autonomous implementation
- `task-boards/` is the human-readable status layer
- `decisions/` records why important choices were made
- `context-bundle-*.md` is task-scoped evidence for downstream agents

Top-level `decisions/` and `task-boards/` are deprecated legacy placeholders, and `helix/` is not the home for workspace artifacts.

## Retrieval Order

1. Read `workspace.yml`
2. Read only the artifact for the phase you are in
3. If a phase artifact is packaged as a folder, start with `index.md`
4. Read annexes or subdocuments only when the index points you there or the main document is insufficient
5. For implementation, prefer the task's context bundle and execution-plan entry over broad workspace scans

## Authoring Rules

- Keep phase entry documents short and navigable
- If PRD or design grows large, split it into `index.md` plus targeted subdocuments
- Move large evidence or inventories into annex files
- Do not require agents to read an entire workspace package to find contracts or decisions
