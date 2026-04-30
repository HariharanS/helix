# Helix Prompt Library

Slash-command prompts. Each is invoked as `/<name>` from Copilot CLI or VS Code chat. Prompts route to an agent (`mode: agent`) or run as a guided dialogue (`mode: ask`). To create a new prompt, run `/hc-maker` with `new prompt for ...`.

## Lifecycle phase prompts

These drive the main Helix workflow (intent → design → tasks → implementation → distill).

| Command | Mode | Routes to | Does |
|---|---|---|---|
| `/hc-jam` | agent | @hc-jam | Refine a fuzzy feature idea into a clear intent that drives a PRD |
| `/hc-tech-design` | agent | @hc-architect | Start technical design from an approved PRD; produces `tech-design/` package |
| `/hc-task-breakdown` | agent | @hc-decomposer | Break a tech design into ralph/fleet/manual tasks + slices |
| `/hc-distill` | agent | @hc-distiller | Distil the active session into delivery memory + runtime learnings + promotion candidates |

## Workspace orchestration prompts

Thin entrypoints for the setup / refresh / maintainer review loop.

| Command | Mode | Routes to | Does |
|---|---|---|---|
| `/hc-setup-workspace` | agent | @hc-setup | Validate workspace inputs, run setup, onboard repos if needed, and report readiness |
| `/hc-refresh-workspace` | agent | @hc-setup | Refresh workspace state, repo capabilities, and CRG readiness after repo changes or onboarding |
| `/hc-review-reusable-patterns` | agent | @hc-setup | Review reusable-pattern evidence and, when appropriate, route through `/hc-skill-synth` before projection or creation |

## Capture-loop prompts

Operator-driven entries that grow the corpus. Tech-agnostic; one screen each.

| Command | Mode | Writes | Does |
|---|---|---|---|
| `/hc-label-session` | ask | `.helix/traces/<id>.label.yml` | Label the most recent trace with `correctness`, `rework`, `notes` (Layer 2 baseline) |
| `/hc-surprise` | ask | `workspaces/{active}/mental-model.md` | Append a dated entry under the workspace's Surprise Log |

## Skill-lifecycle prompts

Maintain `.helix/skills/`. Always operator-initiated — Helix never auto-promotes or auto-graveyards.

| Command | Mode | Writes | Does |
|---|---|---|---|
| `/hc-skill-audit [quarter]` | ask | `.helix/skills/audits/{YYYY-Q#}.md` | Quarterly roll-up of promotions, graveyards, edit-distance trend |
| `/hc-skill-graveyard <id>` | ask | `.helix/skills/graveyard/{id}.md` | Reject a candidate with reason + re-suggest fingerprint |

## Conventions

- **Frontmatter required:** `name`, `description`. `mode: agent` requires `agent:`; `mode: ask` requires `tools:`.
- **One screen per prompt.** Soft cap 30 lines including frontmatter. If a prompt grows past 30 lines it should probably be a skill.
- **Tech-agnostic.** No language, framework, or transport baked in. Operator-supplied paths and commands stay opaque.
- **Active-workspace-aware.** Prompts that write under `.helix/` or `workspaces/` read `.helix/active-workspace.yml` first and stop if no workspace is active.
- **Explicit inputs.** Use `${input:name:description}` at the bottom of the body so Copilot prompts the operator. Required vs optional is documented in the description text.

## Where each prompt's contract lives

| Prompt | Reference doc |
|---|---|
| `/hc-setup-workspace`, `/hc-refresh-workspace`, `/hc-review-reusable-patterns` | [`helix/README.md`](../../README.md), [`helix/docs/cli-workflow.md`](../../docs/cli-workflow.md), and [`helix/.github/agents/hc-setup.agent.md`](../agents/hc-setup.agent.md) |
| `/hc-distill`, `/hc-skill-audit`, `/hc-skill-graveyard` | [`helix/docs/distillation-architecture.md`](../../docs/distillation-architecture.md) |
| `/hc-label-session` | [`helix/docs/label-schema.md`](../../docs/label-schema.md) and [`helix/docs/eval-strategy.md`](../../docs/eval-strategy.md) |
| `/hc-surprise` | [`helix/docs/mental-model-architecture.md`](../../docs/mental-model-architecture.md) and [`helix/templates/mental-model.md.template`](../../templates/mental-model.md.template) |
| `/hc-tech-design`, `/hc-task-breakdown`, `/hc-jam` | The respective agent files in [`helix/.github/agents/`](../agents/) |
