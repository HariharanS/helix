# Helix — Global Conventions

This workspace uses the Helix multi-agent development system.
Helix is a meta-repo that coordinates work across multiple service repos.

## Development Workflow

- Follow the Helix lifecycle: SETUP → JAM → PRD → TECH DESIGN → TASK BREAKDOWN → IMPLEMENTATION → REVIEW → DISTILL
- Treat SETUP as mandatory: create or activate the workspace, sync repos, onboard or refresh repo context, then proceed
- Treat IMPLEMENTATION as nested loops: task-level TDD (`RED → GREEN → REFACTOR → FULL SUITE`) inside scheduler loops (interactive handoff, Ralph loop, or fleet)
- Use task boards (`workspaces/{name}/task-boards/`) to track progress
- Use execution plans (`workspaces/{name}/execution-plans/`) for deterministic autonomous implementation
- Use decisions logs (`workspaces/{name}/decisions/`) to record significant decisions
- Use memory system (`.helix/memory/`) for learnings across sessions
- Check `.helix/active-workspace.yaml` for the current workspace context

## Workspace Model

- Each workspace (`workspaces/{name}/workspace.yaml`) defines repos for a feature or project
- Artifacts (PRD, tech design, execution plans, task boards, decisions) live in the workspace directory
- Code changes are committed to individual repos, not to Helix

## Code Principles

- Domain logic separated from infrastructure
- Pragmatic TDD — meaningful tests, not exhaustive
- Follow each repo's existing coding style — do not impose patterns from other repos
- Keep implementations minimal — do what the task requires, nothing more

## Agent Context

- Read AGENTS.md at repo root for service overview and conventions
- Read .instructions.md files (in `.github/instructions/`) for repo-specific conventions
- Prefer task-specific context bundles over broad repo summaries when implementing a task
- Treat domain claims as evidence-backed only when supported by code, tests, config, or approved design docs
- Each repo's conventions are discovered by the onboard skill — not hardcoded
- Never assume a tech stack — always read repo conventions first

## Context Economy

- Prefer compact markdown and YAML over verbose prose
- Use resilient anchors (`path`, `symbol`, `anchor_text`) instead of path-only references
- Keep persistent instructions narrow and non-obvious
- Omit empty sections and avoid generic best-practice filler
- Move large supporting evidence into annex files instead of the main artifact
