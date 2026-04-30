# AGENTS.md-Only Refactor Handover

Use this prompt when a future agent needs to continue or verify the AGENTS.md-only instruction-surface work in a clean context.

## Handover Prompt

```text
You are continuing the Helix AGENTS.md-only instruction-surface refactor.

Goal:
- Keep `AGENTS.md` as the only default persistent instruction surface.
- Do not reintroduce `.github/copilot-instructions.md`.
- Do not generate `.github/instructions/*.instructions.md` summaries.
- Keep root and nested `AGENTS.md` files concise, layered, and link-heavy.

Source-of-truth rules:
- Read `AGENTS.md` first.
- Read `docs/agents-md-authoring.md` before changing onboarding, setup, or guidance files.
- Treat `scripts/setup-workspace.ps1`, `scripts/install-helix.ps1`, `scripts/doctor.ps1`, and `scripts/Helix.Tools.psm1` as the runtime source of truth.
- Treat `.github/skills/onboard/SKILL.md`, `.github/skills/workspace-sync/SKILL.md`, and `.github/agents/setup.agent.md` as the operator contract.

Do not re-decide:
- `.github/copilot-instructions.md` is removed entirely, not kept as a shim.
- VS Code workspace generation enables AGENTS.md and nested AGENTS.md settings by default.
- Legacy Helix-generated `.instructions.md` summaries are deleted only when they contain the `helix/scripts/setup-workspace.ps1` marker.
- User-authored `.instructions.md` files without that marker are left alone.

Validation:
- Run PowerShell parser checks for changed `.ps1` and `.psm1` files.
- Run `node --test helix/evals/regression/*.test.js`.
- Smoke-test workspace setup in a temp meta repo with `code_review_graph.mode: off`.
- Confirm setup creates no new `.github/instructions/*.instructions.md`, removes legacy generated summaries, preserves user-authored instruction files, and emits a `.code-workspace` with AGENTS settings.
```

## Files To Check

- `scripts/setup-workspace.ps1`
- `scripts/install-helix.ps1`
- `scripts/doctor.ps1`
- `scripts/Helix.Tools.psm1`
- `.github/skills/onboard/SKILL.md`
- `.github/skills/workspace-sync/SKILL.md`
- `.github/agents/setup.agent.md`
- `docs/agents-md-authoring.md`
- `docs/helix-instance-schemas.md`
- `docs/helix-core-meta-repo-model.md`
