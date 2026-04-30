# Helix CLI-First Workflow Guide

This document describes how to run the Helix development lifecycle using **Copilot CLI** as the primary surface.
It is the authoritative reference for both humans and agents working in this meta repo from the CLI.

> **Key constraint:** Sub-agents spawned via the CLI `task` tool cannot use `ask_user`. Only the top-level
> CLI host agent has this capability. Interactive phases must run at the top level; autonomous phases run as sub-agents.

---

## Lifecycle at a Glance

```
SETUP → JAM → PRD → TECH DESIGN → TASK BREAKDOWN → IMPLEMENTATION → REVIEW → DISTILL
```

Each phase writes an artifact. The next phase reads it. The artifact files are the handoff mechanism.

---

## Phase-by-Phase CLI Playbook

### SETUP
**Who runs it:** Host agent (me) OR `setup` sub-agent for automated parts.
**Interactive?** Partially — manifest validation questions need `ask_user`.
**How:**
```
"Set up workspace hpp"
```
Or use the thin prompt:
```
"/hc-setup-workspace"
```
The host agent validates `helix-repos.yml` + `workspace.yml`, runs workspace-setup.ps1, and confirms repo-state, repo-capabilities, MCP config, and CRG graph readiness.
For manifest questions it uses `ask_user` directly. Purely mechanical steps (clone, fetch) can be dispatched to the `setup` sub-agent.

**One active workspace per session:** Exactly one workspace is active at a time, tracked in `.helix/active-workspace.yml`. Switch it explicitly before working on a different feature space.

**Output:**
- `.helix/repo-state/{repo-id}.yml` for each participating repo
- `{workspace}.code-workspace` at the **meta-repo root** (gitignored)
- root and nested `AGENTS.md` guidance in each onboarded repo
- optional maintainer follow-on: reusable-pattern review via `/hc-review-reusable-patterns` when onboarding surfaces cross-repo candidates

Related thin prompts:
- `/hc-refresh-workspace` — rerun setup/refresh after onboarding, branch changes, or repo-state drift
- `/hc-review-reusable-patterns` — review onboarding/distill evidence and route through synth before projection or creation

---

### JAM — Intent Refinement
**Who runs it:** Host agent directly (do NOT dispatch as sub-agent).
**Interactive?** Yes — requires back-and-forth clarification via `ask_user`.
**How:**
```
"Run the JAM phase for workspace hpp"
"Jam on a new feature: <describe your idea>"
```
The host agent conducts the jam session, uses `ask_user` for structured questions, and writes the output.

**Output:** `workspaces/hpp/refined-intent.md`

---

### PRD — Product Requirements
**Who runs it:** Host agent directly, or `planner` sub-agent if intent is clear and Q&A is minimal.
**Interactive?** Partially — needs a few clarification rounds at most.
**How:**
```
"Run the PRD phase for hpp using workspaces/hpp/refined-intent.md"
```
**Auto-curate first:** Before dispatching the planner, spawn an `explore` agent to gather a code-grounded context bundle (model: `claude-haiku-4.5`). Pass the bundle path to the planner. This prevents generic/hallucinated code examples.

Host agent reads refined-intent, explores repos via explorer sub-agent, asks any remaining clarifications via `ask_user`, and writes the PRD.

**Output:** `workspaces/hpp/prd/index.md` (+ subdocs for large features)

---

### TECH DESIGN — Technical Design
**Who runs it:** Host agent directly, or `architect` sub-agent for the research+drafting part.
**Interactive?** Partially — design trade-offs need `ask_user`; codebase research is autonomous.
**How:**
```
"Run the tech design phase for hpp using workspaces/hpp/prd/index.md"
```
**Auto-curate first:** Before dispatching the architect, spawn an `explore` agent to refresh or create a context bundle scoped to the PRD's change surface (model: `claude-haiku-4.5`). Pass the bundle path to the architect — this ensures design decisions are grounded in actual code patterns.

Host agent (or architect sub-agent) explores codebase patterns, drafts the design, then host presents trade-off choices via `ask_user`.

**Output:** `workspaces/hpp/tech-design/index.md` (+ contracts.md, execution-flow.md, etc.)

---

### TASK BREAKDOWN — Decomposition
**Who runs it:** `decomposer` sub-agent — fully autonomous.
**Interactive?** No.
**How:**
```
"Run task breakdown for hpp using workspaces/hpp/tech-design/index.md"
```
Dispatches `decomposer` as a background sub-agent. Returns task board + execution plan.

**Output:**
- `workspaces/hpp/task-boards/hpp.md`
- `workspaces/hpp/execution-plans/hpp.yaml`

---

### IMPLEMENTATION — Ralph Loop (recommended)
**Who runs it:** `@hc-helix` in CLI — this is where it earns its keep as an orchestrator.
**Interactive?** No — fully autonomous.
**How:**
```
"Start the ralph loop for workspace hpp"
"Continue implementation for hpp — next unblocked task"
```
Helix reads the execution plan, picks the highest-priority unblocked task, dispatches `implementer` sub-agent with the task contract + context bundle, then `scribe` marks state. Loops until no eligible tasks remain.

The full implementation loop model (task TDD loop, slice verification loop, review gate) is defined in [`helix-process.md`](./helix-process.md#implementation).

> **Note:** Use fleet mode only when execution plan explicitly marks tasks as parallel-safe with disjoint write paths.

> **Manual mode:** Set `mode: manual` in `workspace.yml` or `execution.mode: manual` in the execution plan to disable autonomous scheduling. Helix will prompt before executing each task. Use this for high-risk changes or when you want to inspect each TDD step.

**Output:** Code commits in product repos, updated task board.

---

### IMPLEMENTATION — Interactive TDD (alternative)
**Who runs it:** `tdd-red` then `implementer` sub-agents, one task at a time.
**How:**
```
"Run TDD red phase for TASK-003 in hpp"
"Now implement TASK-003 to pass the tests"
```
Use this when you want to stay close to each task — inspect failing tests before implementation proceeds.

---

### REVIEW
**Who runs it:** `reviewer` sub-agent — fully autonomous.
**Interactive?** No — produces a structured report; blockers are surfaced in output.
**How:**
```
"Review HPP changes on branch feature/hpp"
"Run review for workspace hpp"
```

**Output:** Review report. Blockers route back to implementation.

---

### DISTILL — Session Learnings
**Who runs it:** `distiller` sub-agent — fully autonomous.
**When:** At the end of a session, or when a phase completes and learnings should be captured.
**How:**
```
"Distill the HPP session"
"Distill learnings from today's implementation"
```

**`/chronicle` (optional, experimental):** If the host runtime provides `/chronicle` output or other session-store-derived summaries, you may pass them to the distiller as supplementary context. They are advisory enrichment only — never the sole source of truth. Workspace artifacts and code changes remain the primary evidence. If `/chronicle` is unavailable or low-signal, omit it.

**Output:** `.helix/memory/episodes/`, `.helix/memory/learnings/`

---

### RESUME — Return to In-Progress Work
**Who runs it:** `resume` sub-agent.
**How:**
```
"Resume work on hpp"
```
Returns a concise briefing: phase, blocked tasks, last completed, suggested next step.

---

## Artifact Chain (Handoff Map)

```
refined-intent.md
    └─▶ prd/index.md
            └─▶ tech-design/index.md
                    └─▶ execution-plans/hpp.yaml  ◀── task-boards/hpp.md
                                └─▶ code (product repos)
                                        └─▶ review report
                                                └─▶ .helix/memory/
```

Each phase reads the previous phase's artifact from `workspaces/hpp/`.

---

## When to Use @hc-helix vs Direct Invocation

| Scenario | Use |
|----------|-----|
| Starting a new feature from scratch | `@hc-helix` — routes to correct phase |
| **Interactive phase (JAM / PRD / design)** | **`@hc-jam`, `@hc-planner`, `@hc-architect` directly** — they run as top-level agents with full `ask_user` capability |
| Autonomous phase (decompose / review / distill) | Invoke specific agent directly, or let `@hc-helix` chain them |
| **Implementation (Ralph loop)** | **`@hc-helix` — orchestrator manages context bundle → implementer → scribe loop** |
| Resuming work | `@hc-resume` then follow its suggested next step |
| Tracking state | `@hc-scribe` (usually spawned automatically by helix/implementer) |

> **Key constraint:** `ask_user` is only available to whichever agent is the **top-level** conversation agent.
> Sub-agents spawned via `task()` **cannot** use `ask_user` regardless of their frontmatter.
> Solution: invoke interactive agents **directly** (`@hc-planner` not `task("...", agent_type="hc-planner")`).
> Context continuity across phases is handled by the **artifact chain** on disk — artifacts are the designed handoff.

---

## Context Hygiene for Interactive Phases

Back-and-forth dialogue in a long JAM or PRD session fills the context window quickly. The rule: **the top-level interactive agent owns only the dialogue — all heavy work is delegated to sub-agents and written to disk**.

```
@hc-planner (top-level)
    │── ask_user: 3 clarifying questions         ← stays in context (small)
    │── task(explorer, background)               ← isolated context, 0 pollution
    │       └─ reads 40 files, runs CRG queries
    │       └─ writes context-bundle.md to disk
    │── reads bundle FILE PATH (not inline)      ← 1 line in context
    │── writes prd/index.md to disk
    └── reports "PRD written to prd/index.md"    ← 1 line in context, not the full PRD
```

**Rules for top-level interactive agents:**

1. **Never read large files inline** — delegate to a sub-agent; read only the written bundle path
2. **Batch ask_user calls** — one structured form per topic, not one question per message
3. **Write artifacts to disk; don't echo them back** — confirm with path only (`"PRD written to workspaces/hpp/prd/index.md"`)
4. **Scope explorer sub-agents tightly** — pass the specific question to answer, not "explore everything"
5. **Use `mode: background` for all research sub-agents** — they run in isolation; main context only gets the result summary

---

## CLI Agent Communication & Handoff

`read_agent` and `write_agent` are available in the CLI host agent (confirmed in v1.0.28). All Helix agents that spawn sub-agents have these in their `tools` list.

### Patterns

| Pattern | When to use |
|---------|-------------|
| `task(mode="background")` + `read_agent` | Long-running analysis; host reads result after completion notification |
| `task(mode="sync")` | Fast, focused prompts expected to finish quickly |
| **File-based handoff** (agent writes bundle to disk; caller reads file path) | Preferred for large context — files persist, are re-usable, and don't bloat host context |
| Direct invocation (`@hc-planner`, `@hc-jam`, `@hc-architect`) | Interactive phases — only pattern that gives sub-agent `ask_user` capability |

### File-Based Handoff (preferred for large context)

For **analysis, review, and context-gathering tasks**, prefer file-based handoff even when `read_agent` is available:

```
task(agent_type="general-purpose", prompt="""
  Review XYZ and write findings to:
  workspaces/{workspace}/reviews/prd-review-{date}.md
  ...
""")
# Then read the file
view("workspaces/{workspace}/reviews/prd-review-{date}.md")
```

**Rules:**
1. Use `general-purpose` (not `rubber-duck`) for thorough reviews — it has file-write tools
2. Include the **explicit output file path** in the prompt
3. Use `mode="background"` — read the file after completion notification
4. Always include full context in the prompt (agent is stateless)

---

## Token Economy Tips

- **Don't route interactive phases through `@hc-helix` in CLI** — the relay pattern wastes 2+ premium requests per question.
- **Keep context bundles task-scoped** — explorer writes them to disk; implementer reads from disk, not inline.
- **Build CRG before planning phases** so JAM, PRD, TECH DESIGN, and TASK BREAKDOWN can navigate code through graph-backed context instead of broad text search.
- **Dispatch explorer as `explore` agent type** (Haiku model) — cheapest way to gather codebase context.

---

## code-review-graph (CRG)

CRG is the default Helix code navigation layer. Init seeds `.vscode/mcp.json` for VS Code project config and bootstraps `~/.copilot/mcp-config.json` for Copilot CLI with `set-context-provider.ps1 -Mode mcp -Bootstrap`. The graph must be built before `hc-curate-context` uses it; if `mode: mcp` is set and the graph is missing, treat that as a setup gap instead of silently falling back to manual scanning.

**Initial setup (run from meta-repo root):**
```powershell
# Normalize MCP config and ensure a usable runtime first
./helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode mcp -Bootstrap

# Register repos (one-time) — use a path, not just an alias
python -m code_review_graph register .\path\to\product-repo --alias RepoAlias
# ... repeat for each repo in the workspace

# Build graph per repo — MUST use a path, NOT the alias name alone (alias-only silently builds 0 nodes)
python -m code_review_graph build --repo .\path\to\product-repo
# If relative path fails, use absolute path:
# python -m code_review_graph build --repo "C:\Users\...\path\to\product-repo"
```

**Validate build succeeded** (non-empty graph > 50 KB):
```powershell
(Get-Item ".\path\to\product-repo\.code-review-graph\graph.db").Length / 1KB
```

**Generate wiki pages** (needed for agent navigation):
```powershell
python -m code_review_graph wiki --repo .\path\to\product-repo
```

**After code changes:**
```powershell
python -m code_review_graph update --repo .\path\to\product-repo
```

**Serve (started automatically by MCP when needed):**
```powershell
python -m code_review_graph serve
```

**Config:** `.helix/context-providers.yml` controls CRG mode and budgets. Normal setup uses `mode: mcp`; `mode: off` is an emergency fallback. Host-specific MCP files are `.vscode/mcp.json` for VS Code and `~/.copilot/mcp-config.json` for Copilot CLI.

---

## LSP Servers

Copilot CLI uses LSP automatically when configured, and the docs position it as **token-efficient** for symbol navigation, references, hover, and rename because it returns compact structured data instead of broad file reads.

- Use LSP as a **language-accurate symbol tool**
- Use CRG as a **structural retrieval and review tool**
- Helix should document and detect LSP, but should not auto-install language servers by default because they are language-specific, environment-specific, and often better owned by the product repo or the operator

## Model Dispatch

When dispatching specialist agents via `task()`, the agent's frontmatter `model:` is **not** auto-applied. You **must** pass the correct `model:` parameter explicitly. Read `.helix/model-config.yml` for tier assignments and use the `task_ids` values:

| Agent | Tier | `model:` parameter |
|-------|------|-------------------|
| jam, planner, architect | reasoning | `claude-opus-4.6` |
| implementer, tdd-red | coding | `gpt-5.3-codex` |
| helix, reviewer, decomposer | analysis | `gpt-5.4` |
| explorer, scribe, distiller, resume | fast | `claude-haiku-4.5` |
| ui-tester | visual (CLI fallback) | `gpt-5.4` |

Example:
```
task("Run PRD for hpp", agent_type="hc-planner", model="claude-opus-4.6", ...)
task("Gather context for hpp", agent_type="explore", model="claude-haiku-4.5", ...)
```

---

## Quick Reference

```
New feature:    "Jam on [idea]"
Next phase:     "Run [prd|tech design|task breakdown] for {workspace}"
Implement:      "Start ralph loop for {workspace}"
One task:       "Run TDD red for TASK-XXX in {workspace}"
Review:         "Review {workspace} changes"
Distill:        "Distill the {workspace} session"
Resume:         "Resume work on {workspace}"
Status:         "What's the current state of workspace {workspace}?"
```

---

## CLI Commands Reference

Future `helix` CLI commands and their current script equivalents. Until the unified CLI is available, invoke the scripts directly from the meta-repo root.

| Future command | Current script | Purpose |
|---|---|---|
| `helix init` | `./helix/scripts/init.ps1` | Bootstrap a new meta repo from helix-core |
| `helix sync` | `./helix/scripts/sync.ps1` | Sync managed files from helix-core into the meta repo |
| `helix upgrade` | `./helix/scripts/upgrade.ps1` | Upgrade the installed Helix version |
| `helix workspace setup` | `./helix/scripts/workspace-setup.ps1` | Clone/attach repos, scan readiness, set active workspace |
| `helix doctor` | `./helix/scripts/doctor.ps1` | Validate install state, manifest schemas, and repo readiness |
