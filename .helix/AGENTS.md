# .helix AGENTS Guide

This directory holds Helix runtime state and memory-like artifacts.

## What Lives Here

- `active-workspace.yml` — current workspace pointer
- `install-state.yml` — what Helix installed into the meta repo (instance-only — created by install-helix)
- `repo-state/` — generated readiness and scan results per repo
- `model-config.yml` — model-to-role assignments
- `context-providers.yml` — optional retrieval providers and token budgets
- `memory/index.md` — entry point to durable learnings
- `memory/episodes/` — episodic session summaries
- `memory/learnings/` — reusable insights

## Read Order

1. Read [`active-workspace.yml`](./active-workspace.yml) when you need current workspace context
2. Read [`install-state.yml`](./install-state.yml) when it exists and you need install and managed-file context
3. Read `repo-state/<repo-id>.yml` when you need readiness or onboarding status for a repo
4. Read [`context-providers.yml`](./context-providers.yml) before assuming optional graph or retrieval tooling is enabled
5. Read [`model-config.yml`](./model-config.yml) when you need role/model assignment context
6. Start memory access at [`memory/index.md`](./memory/index.md)
7. Open specific episode or learning files only if the index points you there

## Retrieval Rules

- Treat memory as distilled guidance, not a raw transcript archive
- Treat `repo-state/` as generated runtime state, not operator-authored config
- Treat `context-providers.yml` as the switch for optional retrieval tooling; if it is off, do not assume graph assistance exists
- Prefer existing learning files over scanning all episodes
- Update or reuse existing learning topics instead of duplicating them
- If you need current feature state, workspace artifacts are usually a better source than memory
