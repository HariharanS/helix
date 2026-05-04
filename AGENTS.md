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

- Helix is installed at the root of a meta-repo (it is not itself the meta-repo). The meta-repo coordinates work; Helix provides the orchestration assets. Product code lives in sibling service repos, not here.
- Workspace-scoped feature artifacts belong under `workspaces/{name}/...`.
- Top-level `decisions/` and `task-boards/` are legacy placeholders, not the active workspace source of truth.
- `execution-plans/` is the machine-readable automation contract.
- `task-boards/` is the human-readable task status layer.
- `context-bundle-*.md` is task-scoped evidence, not general documentation.
- Memory in `.helix/memory/` is distilled and indexed; it is not a raw session log.
- Root `AGENTS.md` should stay navigation-first. Human narrative belongs in `README.md` or `docs/`.
- Installed meta repos use `helix-repos.yml` as the canonical registry name; `repos.yml` survives only as a compatibility alias.
- User-facing script entry points are `scripts/init.ps1`, `scripts/sync.ps1`, `scripts/upgrade.ps1`, and `scripts/workspace-setup.ps1`; the older implementation script names remain for compatibility and internal wiring.
- **Beta:** `.helix/repo-capabilities/{repo-id}.yml` holds generated per-repo capability hints; read when present, skip gracefully when absent.
- **Beta:** `.helix/skills/index.yml` is the projection ledger of skills available in the meta-root for the active workspace. See "Choosing a skill" below for selection rules; `scripts/resolve-skill.ps1` survives only as a developer/CI utility for verifying projection correctness.
- **Beta:** `workspaces/{id}/verification-policy.yml` is an operator-authored slice verification gate policy; opt in by declaring `artifacts.verification_policy` in `workspace.yml`, then read it when present and fall back to task-level `commands.verify` when absent.

## Choosing a skill

All skills available to an agent in the active workspace are visible at the meta root under `.github/skills/`. There is no runtime dispatcher; pick by description, not by hard-coded name.

- `hc-*` are Helix core skills. Stable, always present, invocable by name from any workspace (e.g. `hc-workspace-sync`, `hc-task-board`, `hc-onboard`).
- `hr-*` are Helix-reusable skills. Also present at the meta root and invocable by name.
- Workspace-projected skills are repo-local skills mirrored into the meta root with a `{repo-short}-{skill-name}` prefix (e.g. `mobile-checkout-code-review`). Refer to them by the prefixed name; the un-prefixed form lives in the source repo and is not directly invocable from the meta root.

To select a skill for a task:

1. Read `.helix/skills/index.yml` for the active set; do not enumerate skill names from memory or assume any particular skill is present.
2. Match on the skill's `description` and `argument-hint`, plus its scope (repo / path) when present.
3. Prefer the most specific match. A workspace-projected skill that names the relevant repo and path beats a generic `hr-*` skill.
4. If two skills tie, ask for a narrower scope rather than guessing.
5. Skills marked `projection: never` exist only in their source repo and cannot be invoked from the meta root — note them as available repo-local guidance, not as invocable skills.

## Directory Map

| Path | Purpose | Start With |
|------|---------|------------|
| [`README.md`](./README.md) | Human-first overview | Use for broad orientation, not default implementation context |
| [`./.github/AGENTS.md`](./.github/AGENTS.md) | Agent definitions, skills, prompts, hooks | Use when changing Helix behavior |
| [`./.helix/AGENTS.md`](./.helix/AGENTS.md) | Active workspace, model config, memory | Use when you need runtime or memory context |
| [`./workspaces/AGENTS.md`](./workspaces/AGENTS.md) | Canonical workspace artifact model | Use when reading or writing feature artifacts |
| [`./templates/AGENTS.md`](./templates/AGENTS.md) | Artifact templates and examples | Use when changing generated output shapes |
| [`./docs/AGENTS.md`](./docs/AGENTS.md) | Human-facing guides and roadmap | Use for explanatory docs |
| [`./scripts/AGENTS.md`](./scripts/AGENTS.md) | Helper scripts and hooks | Use when changing automation behavior |
| [`./docs/runtime-surface-contract.md`](./docs/runtime-surface-contract.md) | Where new behavior belongs (script vs. skill vs. agent vs. prompt vs. doc) | Use before adding new behavior or moving content between surfaces |

## Common Entry Points

- Change agent routing or prompt behavior:
  - [`./.github/AGENTS.md`](./.github/AGENTS.md)
- Inspect the active workspace:
  - [`./.helix/AGENTS.md`](./.helix/AGENTS.md)
  - [`./.helix/active-workspace.yml`](./.helix/active-workspace.yml)
- Work on feature artifacts:
  - [`./workspaces/AGENTS.md`](./workspaces/AGENTS.md)
  - `workspaces/{name}/workspace.yml`
- Adjust generated artifact shapes:
  - [`./templates/AGENTS.md`](./templates/AGENTS.md)
- Understand the system as a human:
  - [`README.md`](./README.md)
  - [`./docs/cli-workflow.md`](./docs/cli-workflow.md)
  - [`./docs/helix-process.md`](./docs/helix-process.md)
  - [`./docs/helix-core-meta-repo-model.md`](./docs/helix-core-meta-repo-model.md)
  - [`./docs/helix-instance-schemas.md`](./docs/helix-instance-schemas.md)
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

## Optional Second-Opinion Critique

When Helix is running in a host that provides an optional second-opinion critique capability, it can use that critique sparingly.

- Treat it as a host-runtime capability, not a Helix dependency
- Use it sparingly at high-return checkpoints
- If it materially changes scope, design, or task safety, route back to the correct phase and update the workspace artifacts
