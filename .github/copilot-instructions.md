# Helix — Global Conventions

This workspace uses the Helix multi-agent development system.
In an installed meta repo, use `helix/docs/helix-process.md` as the canonical lifecycle definition and `helix/docs/helix-core-meta-repo-model.md` as the canonical packaging model.

## Execution Rules

- Treat `SETUP` as mandatory before feature work: activate the workspace, attach needed repos, and refresh readiness
- Use workspace artifacts as the source of truth for feature delivery
- Keep code changes in product repos, not in Helix
- Use task boards (`workspaces/{name}/task-boards/`) for human status
- Use execution plans (`workspaces/{name}/execution-plans/`) for deterministic autonomous implementation
- Use decisions logs (`workspaces/{name}/decisions/`) for significant decisions
- Treat root `decisions/` and `task-boards/` as deprecated legacy placeholders, not active artifact destinations
- Use memory in `.helix/memory/` for distilled learnings, not raw transcripts
- Check `.helix/active-workspace.yml` for current workspace context; if `active:` is set, read `workspaces/{active}/AGENTS.md` and any AGENTS.md files in subdirectories of that workspace folder before starting work
- When an optional second-opinion critique capability is available, use it sparingly at high-return checkpoints and treat it as advisory only
- When operating from Copilot CLI, read `helix/docs/cli-workflow.md` for the phase-by-phase CLI playbook — it defines which phases run at the top level vs as sub-agents
- **Model dispatch:** When dispatching specialist agents via `task()`, always read `.helix/model-config.yml` and pass the correct `model:` using the `task_ids` values — agent frontmatter `model:` is NOT auto-applied by the `task()` tool
- **Code exploration:** Before PRD, TECH DESIGN, or TASK BREAKDOWN phases, spawn the `explorer` agent with the `/curate-context` skill to build a code-grounded context bundle; never assert code facts without this step when `code_review_graph.mode` is `full`
- **Lifecycle agent:** For autonomous phases (TASK BREAKDOWN, IMPLEMENTATION, REVIEW, DISTILL), prefer `@helix` for orchestration. For interactive phases (JAM, PRD, TECH DESIGN), invoke the specialist agent **directly** (`@jam`, `@planner`, `@architect`) — direct invocation gives them top-level `ask_user` capability; never dispatch these as `task()` sub-agents in CLI

## Code Principles

- Domain logic separated from infrastructure
- Pragmatic TDD — meaningful tests, not exhaustive
- Follow each repo's existing coding style — do not impose patterns from other repos
- Keep implementations minimal — do what the task requires, nothing more

## Agent Context

- Read root `AGENTS.md` for the repo map, then prefer the nearest relevant `AGENTS.md` in the subtree you are touching
- Read .instructions.md files (in `.github/instructions/`) for repo-specific conventions
- Read `.helix/context-providers.yml` before assuming optional retrieval tooling is available or desired
- Prefer task-specific context bundles over broad repo summaries when implementing a task
- Prefer index or summary documents over annexes or large blob files when both exist
- Treat domain claims as evidence-backed only when supported by code, tests, config, or approved design docs
- Each repo's conventions are discovered by the onboard skill — not hardcoded
- Never assume a tech stack — always read repo conventions first
- If `code_review_graph.mode` is `review-only`, use graph retrieval only for review, blast-radius, and changed-file scoping
- If `code_review_graph.mode` is `full` and its MCP tools are available, prefer targeted graph queries over broad code scans, but stay inside the configured tool-call and token budget
- If graph retrieval is disabled, unavailable, or noisy, fall back immediately to manual repo search and context bundles

## Context Economy

- Prefer compact markdown and YAML over verbose prose
- Use resilient anchors (`path`, `symbol`, `anchor_text`) instead of path-only references
- Keep persistent instructions narrow and non-obvious
- Omit empty sections and avoid generic best-practice filler
- Move large supporting evidence into annex files instead of the main artifact
- For code-review-graph, prefer minimal-detail calls and targeted entity queries over broad list or dump-style retrieval
