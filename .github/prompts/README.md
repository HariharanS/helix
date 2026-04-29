# Helix Prompt Library

Slash-command prompts. Each is invoked as `/<name>` from Copilot CLI or VS Code chat. Prompts route to an agent (`mode: agent`) or run as a guided dialogue (`mode: ask`). To create a new prompt, run `/maker` with `new prompt for ...`.

## Lifecycle phase prompts

These drive the main Helix workflow (intent → design → tasks → implementation → distill).

| Command | Mode | Routes to | Does |
|---|---|---|---|
| `/jam` | agent | @jam | Refine a fuzzy feature idea into a clear intent that drives a PRD |
| `/tech-design` | agent | @architect | Start technical design from an approved PRD; produces `tech-design/` package |
| `/task-breakdown` | agent | @decomposer | Break a tech design into ralph/fleet/manual tasks + slices |
| `/distill` | agent | @distiller | Distil the active session into delivery memory + runtime learnings + promotion candidates |

## Capture-loop prompts

Operator-driven entries that grow the corpus. Tech-agnostic; one screen each.

| Command | Mode | Writes | Does |
|---|---|---|---|
| `/label-session` | ask | `.helix/traces/<id>.label.yml` | Label the most recent trace with `correctness`, `rework`, `notes` (Layer 2 baseline) |
| `/surprise` | ask | `workspaces/{active}/mental-model.md` | Append a dated entry under the workspace's Surprise Log |

## Skill-lifecycle prompts

Maintain `.helix/skills/`. Always operator-initiated — Helix never auto-promotes or auto-graveyards.

| Command | Mode | Writes | Does |
|---|---|---|---|
| `/skill-audit [quarter]` | ask | `.helix/skills/audits/{YYYY-Q#}.md` | Quarterly roll-up of promotions, graveyards, edit-distance trend |
| `/skill-graveyard <id>` | ask | `.helix/skills/graveyard/{id}.md` | Reject a candidate with reason + re-suggest fingerprint |

## Conventions

- **Frontmatter required:** `name`, `description`. `mode: agent` requires `agent:`; `mode: ask` requires `tools:`.
- **One screen per prompt.** Soft cap 30 lines including frontmatter. If a prompt grows past 30 lines it should probably be a skill.
- **Tech-agnostic.** No language, framework, or transport baked in. Operator-supplied paths and commands stay opaque.
- **Active-workspace-aware.** Prompts that write under `.helix/` or `workspaces/` read `.helix/active-workspace.yml` first and stop if no workspace is active.
- **Explicit inputs.** Use `${input:name:description}` at the bottom of the body so Copilot prompts the operator. Required vs optional is documented in the description text.

## Where each prompt's contract lives

| Prompt | Reference doc |
|---|---|
| `/distill`, `/skill-audit`, `/skill-graveyard` | [`helix/docs/distillation-architecture.md`](../../docs/distillation-architecture.md) |
| `/label-session` | [`helix/docs/label-schema.md`](../../docs/label-schema.md) and [`helix/docs/eval-strategy.md`](../../docs/eval-strategy.md) |
| `/surprise` | [`helix/docs/mental-model-architecture.md`](../../docs/mental-model-architecture.md) and [`helix/templates/mental-model.md.template`](../../templates/mental-model.md.template) |
| `/tech-design`, `/task-breakdown`, `/jam` | The respective agent files in [`helix/.github/agents/`](../agents/) |
