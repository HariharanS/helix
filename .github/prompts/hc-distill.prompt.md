---
name: hc-distill
description: Run the distiller against the active workspace; accumulate evidence in .helix/skills/candidates/, respect the graveyard
mode: agent
agent: hc-distiller
tools: ['read', 'edit', 'search/codebase']
---

VS Code chat entrypoint to the `hc-distiller` agent. Distil the active workspace's most recent session(s) into delivery memory, runtime learnings, and promotion candidates.

Authoritative sources (do not duplicate here):

- Schemas, gates, graveyard rules, persistence layout, and triggers — `helix/docs/distillation-architecture.md`.
- Role and decision rules (graveyard check, append-only candidates, recommend-don't-promote) — `helix/.github/agents/hc-distiller.agent.md`.

Local rules for this entrypoint:

- Read `.helix/active-workspace.yml` first. If no workspace is active, ask the operator which to distil and stop until answered.
- Do NOT generate or project a skill from this prompt. When a candidate looks ready, recommend `/hc-review-reusable-patterns` for maintainer review (which may invoke `/hc-skill-synth`); on `PROJECT EXISTING` point at `helix/scripts/promote-skill.ps1`, on `CREATE NEW` / `ADD TO EXISTING` point at `/hc-maker`.

${input:scope:Optional — feature slug to distil instead of the most recent session}
