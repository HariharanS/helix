# Helix Platform Roadmap

Last updated: 2026-04-09

## Goal

Evolve Helix from a strong prompt-and-doc orchestration scaffold into a robust multi-agent control plane for GitHub Copilot:

- self-learning over time
- memory-backed and memory-provider agnostic
- typed and predictable at control-plane boundaries
- observable, governable, and eval-driven
- usable through both a CLI and an SDK

## North Star

Helix should become a system where:

- a user can point Helix at one or more repos and get safe orchestration, not just better prompts
- every agent action produces structured state, traces, and learnings
- model choice is driven by measured task performance, budget, and latency constraints
- memory can be swapped without rewriting agents
- critical control-plane outputs are typed and validated
- GitHub Copilot is the first execution backend, not the only one forever

## Keep From Current Helix

These are already strong and should stay central:

- workspace-first multi-repo model
- setup-first delivery flow: SETUP -> JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
- execution plans with explicit ownership and done criteria
- tech-agnostic onboarding via repo discovery
- explicit model tiers per agent role
- context bundles as compact task-scoped evidence

## Borrow Aggressively From Squad

These are the areas where Helix should catch up fast:

- real CLI lifecycle commands: `init`, `status`, `doctor`, `upgrade`
- runtime governance enforced in code, not only in prompts
- import/export and portable state
- observability and trace collection
- SDK-first configuration and embedding
- durable runtime state for orchestration loops

## Architecture Principles

1. The runtime owns orchestration state. Markdown is for humans, not for the scheduler.
2. Prompts should express intent. Policies, routing, and state transitions should live in code.
3. Every durable artifact should have a schema.
4. Memory is a subsystem with an interface, not a folder layout.
5. Evals come after traces exist.
6. Model routing must be measurement-driven, not vibe-driven.
7. BAML belongs at control-plane boundaries, not everywhere.

## Recommended Phase Plan

### Phase 0: Harden The Foundation

Objective: make Helix operable and cross-platform before adding more intelligence.

Deliverables:

- add a real typed runtime package in TypeScript for workspace and execution-plan handling
- replace brittle shell and line-based YAML parsing with proper parsers
- introduce schemas for:
  - workspace definition
  - execution plan
  - task contract
  - decision entry
  - episode
  - learning
  - run trace
- add a minimal `helix status` and `helix doctor`
- add a single source of truth for active workspace and run state

Exit criteria:

- workspace activation, validation, and sync work on Windows and Unix
- no critical runtime behavior depends on ad hoc markdown parsing
- Helix can verify that a workspace is runnable before orchestration starts

### Phase 1: Build The Runtime Control Plane

Objective: move orchestration from agent prose into executable runtime logic.

Deliverables:

- `AgentRunner` abstraction for Copilot-backed agents
- runtime scheduler for:
  - interactive mode
  - Ralph loop
  - fleet mode
- structured event log for all runs
- durable orchestration state:
  - queued tasks
  - in-flight tasks
  - blocked tasks
  - completed tasks
  - agent outcomes
- write ownership enforcement from execution plans
- first-class support for task retries, pause, resume, and escalation

Exit criteria:

- one feature can move from execution plan to task completion without manual state editing
- Ralph loop decisions are reproducible from structured state
- fleet mode rejects overlapping write ownership automatically

### Phase 2: Add Governance And Observability

Objective: make Helix safe enough to trust and transparent enough to debug.

Deliverables:

- policy engine for:
  - allowed write paths
  - blocked shell commands
  - reviewer lockout
  - approval gates
  - secret and PII scrubbing
- audit log for every tool call and state transition
- OpenTelemetry-based trace capture
- run metadata:
  - agent
  - model
  - prompt version
  - latency
  - token usage
  - cost estimate
  - test outcomes
  - human intervention count
- `helix doctor` checks for policies, state integrity, missing artifacts, and stale workspaces

Exit criteria:

- every run can be reconstructed from logs and traces
- unsafe actions are blocked by runtime policy rather than prompt wording
- failures are diagnosable without reading raw chat history

### Phase 3: Build A Real Memory Subsystem

Objective: make memory pluggable, retrieval-aware, and useful for future runs.

Deliverables:

- define a `MemoryStore` interface with operations like:
  - append episode
  - upsert learning
  - search learnings
  - retrieve task context
  - compact old context
  - export and import memory
- ship filesystem adapter first
- add optional adapters later:
  - SQLite
  - vector store
  - graph store if justified
- separate memory types:
  - episodic
  - semantic learnings
  - repo conventions
  - evaluation history
  - prompt and model performance history
- make distillation structured and trace-linked

Exit criteria:

- agents consume memory through one interface
- swapping memory backends does not require prompt rewrites
- retrieval is scoped by task type, repo, and phase instead of dumping generic history

### Phase 4: Add Typed Contracts With BAML

Objective: make the control plane predictable where free-form output is currently risky.

Use BAML first for:

- planner outputs
- architect outputs
- decomposer task contracts
- reviewer findings
- distiller episodes and learnings
- resume briefings

Avoid using BAML first for:

- raw coding output
- broad exploratory research
- open-ended JAM conversations

Deliverables:

- BAML schemas for control-plane artifacts
- generated validators and parsers
- runtime rejection and retry path for invalid outputs
- versioned contract definitions

Exit criteria:

- the scheduler never depends on hand-parsed markdown for critical task state
- invalid structured output fails fast and retries cleanly

### Phase 5: Add Evals, DSPy, And Model Routing

Objective: optimize prompts and model selection using measured performance.

Deliverables:

- task taxonomy:
  - planning
  - design
  - decomposition
  - exploration
  - coding
  - review
  - distillation
- eval dataset built from real Helix traces and human corrections
- offline eval harness with fixed scenarios and scoring
- prompt version registry
- DSPy-based prompt optimization for bounded tasks
- model router that considers:
  - task type
  - historical win rate
  - budget ceiling
  - latency target
  - context size
  - required modalities
- policy for fallback chains and automatic downgrade or upgrade

Key rule:

- do not optimize prompts before trace capture and scoring are stable

Exit criteria:

- Helix can explain why a model was chosen
- routing decisions are backed by eval scores and budget rules
- prompt changes can be compared against a baseline before rollout

### Phase 6: Ship A Proper CLI And SDK

Objective: make Helix usable as a product and embeddable as a platform.

CLI targets:

- `helix init`
- `helix workspace create`
- `helix workspace sync`
- `helix workspace activate`
- `helix run`
- `helix resume`
- `helix status`
- `helix doctor`
- `helix export`
- `helix import`

SDK targets:

- instantiate a runtime
- register agent runners
- register memory adapters
- register policies
- register model routers
- subscribe to traces and events
- drive runs programmatically from another tool

Exit criteria:

- Helix can be used without manually editing repo internals
- another application can embed Helix as an orchestration engine

## Priority Order

If time or focus is limited, do the work in this order:

1. runtime control plane
2. governance and observability
3. memory interface
4. CLI and doctor/status ergonomics
5. BAML for control-plane outputs
6. evals and DSPy optimization
7. plugin system and ecosystem work

## What To Delay On Purpose

These are useful, but should not come before the core runtime is stable:

- plugin marketplace
- third-party extension APIs
- fancy memory backends without a proven interface
- DSPy tuning for tasks that still lack good scoring
- broad BAML adoption outside control-plane outputs
- autonomous fleet by default

## Immediate 30-Day Backlog

### P0

- create a TypeScript runtime package for state and orchestration primitives
- define schemas for workspace, task contract, run trace, episode, and learning
- replace the remaining legacy `scripts/setup-workspace.sh` helper with the typed runtime path built on the newer PowerShell installer/setup flow
- add `helix status` and `helix doctor`
- add JSONL event logging for all hooks and agent runs
- enforce write-path and blocked-command policy in runtime code

### P1

- add filesystem-backed `MemoryStore`
- make distillation emit structured episodes and learnings
- add OpenTelemetry traces and cost metadata
- define BAML contracts for decomposer, reviewer, distiller, and resume
- add export/import for workspace state and memory

### P2

- build eval harness and prompt registry
- define task taxonomy and scoring rubrics
- add first model router with budget and fallback rules
- add DSPy optimization for decomposer and reviewer prompts

## Suggested Package Layout

```text
packages/
  helix-core/          # runtime, scheduler, policies, state machine
  helix-cli/           # user-facing commands
  helix-sdk/           # embeddable API
  helix-schemas/       # zod/json-schema/baml contracts
  helix-memory-fs/     # filesystem adapter
  helix-memory-sqlite/ # optional durable local adapter
  helix-evals/         # datasets, scorers, benchmarks
  helix-copilot/       # Copilot runner integration
```

## Success Metrics

Track these from the start:

- task success rate by phase and model
- average human interventions per completed task
- percentage of invalid structured outputs
- rerun rate caused by missing context or bad task contracts
- test pass rate after first implementation attempt
- cost per completed task
- memory retrieval hit rate
- time to resume a paused feature

## Final Recommendation

Helix should not try to out-Squad Squad by copying repo-local team ergonomics first.

Helix should win by becoming:

- the better multi-repo execution engine
- the safer autonomous delivery runtime
- the better memory and eval platform for Copilot-backed agents
- the control plane that can later expose both a CLI and an SDK

That path fits the current Helix architecture and the long-term goal much better than chasing cosmetic parity first.
