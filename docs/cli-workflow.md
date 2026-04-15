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
The host agent validates `repos.yml` + `workspace.yml`, runs setup-workspace.ps1, and confirms repo-state.  
For manifest questions it uses `ask_user` directly. Purely mechanical steps (clone, fetch) can be dispatched to the `setup` sub-agent.

**Output:** `.helix/repo-state/{repo-id}.yml` for each repo, `workspaces/hpp/hpp.code-workspace`

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
**Who runs it:** `@helix` in CLI — this is where it earns its keep as an orchestrator.  
**Interactive?** No — fully autonomous.  
**How:**
```
"Start the ralph loop for workspace hpp"
"Continue implementation for hpp — next unblocked task"
```
Helix reads the execution plan, picks the highest-priority unblocked task, dispatches `implementer` sub-agent with the task contract + context bundle, then `scribe` marks state. Loops until no eligible tasks remain.

> **Note:** Use fleet mode only when execution plan explicitly marks tasks as parallel-safe with disjoint write paths.

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

## When to Use @helix vs Direct Invocation

| Scenario | Use |
|----------|-----|
| Starting a new feature from scratch | Talk to host directly: `"Start HPP feature"` |
| Interactive phase (JAM / PRD / design) | Host agent directly — needs `ask_user` |
| Autonomous phase (decompose / review / distill) | Invoke specific agent directly |
| **Implementation (Ralph loop)** | **`@helix` — only phase where orchestrator adds real value in CLI** |
| Resuming work | `resume` sub-agent, then follow its suggested next step |
| Tracking state | `scribe` sub-agent (usually spawned automatically by helix/implementer) |

---

## Token Economy Tips

- **Don't route interactive phases through `@helix` in CLI** — the relay pattern wastes 2+ premium requests per question.
- **Keep context bundles task-scoped** — explorer writes them to disk; implementer reads from disk, not inline.
- **Use `--skip-flows` on CRG builds** for fast initial indexing; run full build later for community/flow detection.
- **Dispatch explorer as `explore` agent type** (Haiku model) — cheapest way to gather codebase context.

---

## code-review-graph (CRG)

CRG is installed and configured. The graph must be built before `curate-context` uses it (otherwise falls back to manual scanning with `confidence: low`).

**Initial setup:**
```powershell
# Register repos (one-time)
python -m code_review_graph register .\Rapid.Api.PaymentRequest --alias PaymentRequest
python -m code_review_graph register .\Rapid.Api.SecurePanel --alias SecurePanel
# ... etc for each repo

# Build graph per repo
python -m code_review_graph build --repo .\Rapid.Api.PaymentRequest
# ... etc
```

**After code changes:**
```powershell
python -m code_review_graph update --repo .\Rapid.Api.PaymentRequest
```

**Serve (started automatically by MCP when needed):**
```powershell
python -m code_review_graph serve
```

**Config:** `.helix/context-providers.yml` — set `mode: off` to disable CRG and always use manual fallback.

---

## Quick Reference

```
New feature:    "Jam on [idea]"
Next phase:     "Run [prd|tech design|task breakdown] for hpp"
Implement:      "Start ralph loop for hpp"
One task:       "Run TDD red for TASK-XXX in hpp"
Review:         "Review hpp changes"
Distill:        "Distill the hpp session"
Resume:         "Resume work on hpp"
Status:         "What's the current state of workspace hpp?"
```
