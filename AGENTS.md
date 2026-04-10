# Helix AGENTS Guide

Use this file to discover where relevant context lives in the Helix meta-repo.

Full human-facing overview: [`README.md`](./README.md)

## Read Order

1. Read this file for repo map and source-of-truth rules
2. Read the nearest relevant subfolder `AGENTS.md`
3. Read only the targeted artifact, config, or prompt file for the task
4. If a document package has an `index.md`, start there
5. Open annexes or supporting docs only when the index or main file is insufficient

Do **not** read the entire repo by default.

## Core Invariants

- Helix is a meta-repo. Product code lives in sibling service repos, not here.
- Workspace-scoped feature artifacts belong under `workspaces/{name}/...`.
- Top-level `decisions/` and `task-boards/` are legacy placeholders, not the active workspace source of truth.
- `execution-plans/` is the machine-readable automation contract.
- `task-boards/` is the human-readable task status layer.
- `context-bundle-*.md` is task-scoped evidence, not general documentation.
- Memory in `.helix/memory/` is distilled and indexed; it is not a raw session log.
- Root `AGENTS.md` should stay navigation-first. Human narrative belongs in `README.md` or `docs/`.

## Directory Map

| Path | Purpose | Start With |
|------|---------|------------|
| [`README.md`](./README.md) | Human-first overview | Use for broad orientation, not default implementation context |
| [`./.github/AGENTS.md`](./.github/AGENTS.md) | Agent definitions, skills, prompts, global instructions | Use when changing Helix behavior |
| [`./.helix/AGENTS.md`](./.helix/AGENTS.md) | Active workspace, model config, memory | Use when you need runtime or memory context |
| [`./workspaces/AGENTS.md`](./workspaces/AGENTS.md) | Canonical workspace artifact model | Use when reading or writing feature artifacts |
| [`./templates/AGENTS.md`](./templates/AGENTS.md) | Artifact templates and examples | Use when changing generated output shapes |
| [`./docs/AGENTS.md`](./docs/AGENTS.md) | Human-facing guides and roadmap | Use for explanatory docs |
| [`./scripts/AGENTS.md`](./scripts/AGENTS.md) | Helper scripts and hooks | Use when changing automation behavior |

## Common Entry Points

- Change agent routing or prompt behavior:
  - [`./.github/AGENTS.md`](./.github/AGENTS.md)
  - [`./.github/copilot-instructions.md`](./.github/copilot-instructions.md)
- Inspect the active workspace:
  - [`./.helix/AGENTS.md`](./.helix/AGENTS.md)
  - [`./.helix/active-workspace.yaml`](./.helix/active-workspace.yaml)
- Work on feature artifacts:
  - [`./workspaces/AGENTS.md`](./workspaces/AGENTS.md)
  - `workspaces/{name}/workspace.yaml`
- Adjust generated artifact shapes:
  - [`./templates/AGENTS.md`](./templates/AGENTS.md)
- Understand the system as a human:
  - [`README.md`](./README.md)
  - [`./docs/helix-process.md`](./docs/helix-process.md)
  - [`./docs/helix-core-meta-repo-model.md`](./docs/helix-core-meta-repo-model.md)
  - [`./docs/starting-cross-repo-feature-with-helix.md`](./docs/starting-cross-repo-feature-with-helix.md)

## Retrieval Discipline

- Prefer the nearest relevant `AGENTS.md` over a broad repo scan
- Prefer canonical artifact files over explanatory docs
- Prefer `index.md` plus targeted subdocuments over giant single-file reads when available
- For implementation, prefer the execution-plan task entry and its context bundle over broad workspace artifacts
- Read memory through `.helix/memory/index.md` before opening individual episodes or learnings

## Current Structure Notes

- Workspace artifact packaging is evolving. Some phases still default to single files such as `prd.md` and `tech-design.md`.
- When those artifacts grow large, prefer an indexed package structure instead of inflating a single blob.
- The explorer bundle model already supports progressive disclosure through a main bundle plus optional annex.

## Optional Copilot Rubber Duck

When Helix is running inside GitHub Copilot CLI experimental mode, it can use Rubber Duck as an optional second opinion.

- Treat it as a host-runtime capability, not a Helix dependency
- Use it sparingly at high-return checkpoints
- If it materially changes scope, design, or task safety, route back to the correct phase and update the workspace artifacts
