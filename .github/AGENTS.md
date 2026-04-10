# .github AGENTS Guide

Use this directory when changing how Helix behaves.

## What Lives Here

- `copilot-instructions.md` — global guidance applied across the repo
- `agents/` — specialist agent definitions and routing behavior
- `skills/` — reusable workflows and phase mechanics
- `prompts/` — reusable prompt/output scaffolds

## Read Order

1. Read [`../AGENTS.md`](../AGENTS.md) for repo-level source-of-truth rules
2. Read [`copilot-instructions.md`](./copilot-instructions.md) for global behavior
3. Read only the relevant subtree:
   - `agents/` when changing agent responsibilities or routing
   - `skills/` when changing reusable workflows
   - `prompts/` when changing reusable output shapes

## Editing Rules

- Put global rules in `copilot-instructions.md`, not repeated across every agent file
- Keep the full Helix lifecycle and packaging story in `../docs/helix-process.md` and `../docs/helix-core-meta-repo-model.md`, not in `copilot-instructions.md`
- Keep agent files role-focused; avoid turning them into long human documentation
- Keep skills procedural and reusable; do not hide product-specific context inside them
- Keep prompts as scaffolds, not policy engines
- Prefer adding targeted guidance in the nearest relevant file over inflating repo-root docs
