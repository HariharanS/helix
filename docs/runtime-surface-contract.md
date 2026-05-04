# Runtime Surface Contract

Date: 2026-05-04
Status: Active contract.

This document is the canonical reference for **where new behavior belongs** in Helix. When extending Helix — a script, a skill, an agent role, a prompt, a doc, an `AGENTS.md` — consult this contract first and pick the surface that owns the behavior. Implementation details live in **one** primary surface. Other surfaces link to that owner instead of duplicating its content.

This contract is the structural rule that several concurrent cleanups are converging on (router removal, projection generalization, setup/distillation de-duplication). See the relevant plans for each:

- [`runtime-surface-and-skill-index-refactor-plan.md`](./runtime-surface-and-skill-index-refactor-plan.md)
- [`skill-projection-and-simplification-plan.md`](./skill-projection-and-simplification-plan.md)

## Surface Ownership

| Surface | Owns | Must Not Own |
|---|---|---|
| **Script** (`helix/scripts/*.ps1`, `*.psm1`) | Deterministic state mutation, generation, validation | Long explanatory workflow prose, role identity |
| **Skill** (`helix/.github/skills/*/SKILL.md`) | Reusable operational procedure or playbook | Role identity, orchestration routing, schema rationale |
| **Agent** (`helix/.github/agents/*.agent.md`) | Role, gates, dispatch rules, handoffs, hard safety rules | Full procedure text already owned by a skill or script |
| **Prompt** (`helix/.github/prompts/*.prompt.md`) | Thin host-specific entrypoint (VS Code chat) | Full workflow or schema duplication |
| **Doc** (`helix/docs/*.md`) | Rationale, schema, examples, migration notes, narrative | Runtime state mutation |
| **`AGENTS.md`** (any directory) | Durable navigation and non-obvious operating rules | Feature requirements, copied README content, broad narrative |

## Placement Rules

1. **Implementation details live in exactly one primary surface.** Other surfaces link to the owner. If you find the same procedure in a script, a skill, and a prompt, only one is canonical and the rest must link.
2. **Prompts are host-specific entrypoints, not canonical contracts.** A `.prompt.md` is a thin wrapper that VS Code chat surfaces as a slash command. Behavior, schema, and gate rules live elsewhere; the prompt invokes them.
3. **Scripts mutate state. Skills describe procedure. Agents enforce roles.** When a behavior crosses two surfaces, the lower-level one is the owner and the higher-level one links to it. Skill links to script. Agent links to skill.
4. **`AGENTS.md` is for navigation and non-obvious rules, not narrative.** Long explanations belong in `helix/docs/`. Use `AGENTS.md` to point readers to the canonical owner.
5. **No surface should restate a schema another surface owns.** Schemas live in `helix/docs/helix-instance-schemas.md` (and adjacent docs). Skills, agents, and prompts link.

## Examples

### Good Placement

- **Setup procedure**: lives in `hc-workspace-sync/SKILL.md`. `hc-setup.agent.md` links to it and adds gate rules. `setup-workspace.ps1` is the script the skill invokes. `hc-setup-workspace.prompt.md` is the VS Code wrapper that calls the agent.
- **Distillation schemas**: live in `docs/distillation-architecture.md`. `hc-distiller.agent.md` links to it and adds decision rules. `hc-distill.prompt.md` is the VS Code wrapper.
- **Skill index schema**: lives in `docs/helix-instance-schemas.md`. `Helix.Tools.psm1` reads/writes the file. `meta-repo-skills-management.md` explains the rationale and links to the schema doc.

### Bad Placement

- A prompt file that restates the full distillation schema. (Schema belongs in the doc; the prompt should link.)
- An agent file that restates the full setup procedure. (Procedure belongs in the skill; the agent should link.)
- A skill file that contains role identity and orchestration routing rules. (Role belongs in the agent.)
- An `AGENTS.md` that contains a multi-paragraph narrative of how Helix works. (Narrative belongs in `README.md` or `docs/`.)
- A script doc-string that documents the workspace artifact model. (Artifact model belongs in `workspaces/AGENTS.md` and the schema doc.)

## How To Decide

Ask the questions in this order:

1. **Does this mutate state on disk?** If yes, the owner is a script. Other surfaces link to it.
2. **Is this a reusable procedure that an agent or operator runs?** If yes, the owner is a skill.
3. **Is this a role, gate, or handoff rule?** If yes, the owner is an agent file.
4. **Is this narrative, schema, or rationale?** If yes, the owner is a doc.
5. **Is this a VS Code chat entrypoint that just dispatches to an agent or skill?** If yes, the owner is a prompt file — and it must stay thin.
6. **Is this navigation guidance ("if you are an agent, read X next")?** If yes, the owner is an `AGENTS.md`.

If two of these answer "yes", split the behavior across the matching surfaces and link the higher-level one to the lower-level owner. If you cannot tell where it belongs, the default is the lowest applicable surface (script over skill, skill over agent, doc over `AGENTS.md`).

## When This Contract Changes

This document is itself a Helix doc, owned by `helix/docs/`. Update it when surface ownership rules change. Do not restate this contract in skills, agents, or prompts — link here instead.
