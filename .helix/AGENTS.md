# .helix AGENTS Guide

This directory holds Helix runtime state and memory-like artifacts.

## What Lives Here

- `active-workspace.yaml` — current workspace pointer
- `model-config.yaml` — model-to-role assignments
- `memory/index.md` — entry point to durable learnings
- `memory/episodes/` — episodic session summaries
- `memory/learnings/` — reusable insights

## Read Order

1. Read [`active-workspace.yaml`](./active-workspace.yaml) when you need current workspace context
2. Read [`model-config.yaml`](./model-config.yaml) when you need role/model assignment context
3. Start memory access at [`memory/index.md`](./memory/index.md)
4. Open specific episode or learning files only if the index points you there

## Retrieval Rules

- Treat memory as distilled guidance, not a raw transcript archive
- Prefer existing learning files over scanning all episodes
- Update or reuse existing learning topics instead of duplicating them
- If you need current feature state, workspace artifacts are usually a better source than memory
