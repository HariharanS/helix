# Helix Process

This is the canonical description of the Helix delivery process.

Use this document when you need the full lifecycle, loops, artifacts, and phase boundaries. Keep shorter summaries elsewhere and link back here instead of rewriting the process in multiple files.

## Core Ideas

- Helix is workspace-first. Feature artifacts live in a workspace or feature-space, not in product repos.
- Product repos stay focused on product code, tests, and local repo conventions.
- Helix runs a staged process with explicit loops and gates rather than one giant prompt.
- Each phase should produce a small, discoverable artifact set that the next phase can consume.

## Lifecycle

```text
SETUP -> JAM -> [AUTO-CURATE] -> PRD -> [AUTO-CURATE] -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
```

Auto-curation uses the `/curate-context` skill (backed by code-review-graph) to produce tiered context bundles before planning phases. Skipped when context already exists or intent is still vague (JAM phase).

## Phase Contract

| Phase | Purpose | Primary Output | Notes |
|------|---------|----------------|------|
| `SETUP` | Attach repos, refresh status, verify readiness | workspace context + repo readiness state | No feature design yet |
| `JAM` | Refine a vague idea into a sharp intent | `refined-intent.md` | Keep this short |
| `PRD` | Define user value, requirements, AC, risks | `prd.md` or `prd/index.md` | Package larger PRDs |
| `TECH DESIGN` | Lock contracts, repo boundaries, rollout approach | `tech-design.md` or `tech-design/index.md` | Package larger designs |
| `TASK BREAKDOWN` | Create safe implementation units and execution contracts | task board + `execution-plan.yaml` | One repo per task |
| `IMPLEMENTATION` | Execute tasks with TDD and scheduler loops | code changes in product repos | Driven by execution plan |
| `REVIEW` | Run quality gates and surface blockers | review findings + task updates | Can send work back |
| `DISTILL` | Preserve learnings and state for later runs | decisions, episodes, learnings | Memory is structured, not raw chat |

## Phase Loops

### `SETUP`

- read repo registry
- attach or clone only the repos needed now
- inspect repo readiness and update `.helix/repo-state/`
- onboard only repos that are not Helix-ready
- register repos with code-review-graph and build graphs (via workspace-sync skill)
- confirm active workspace

### `JAM`

- restate the request
- inspect code only when it changes scope or constraints
- clarify unknowns
- reduce ambiguity until intent is testable

### `PRD`

- gather evidence
- define stories and acceptance criteria
- resolve missing decisions
- split supporting detail into subdocs or annexes when needed

### `TECH DESIGN`

- inspect existing patterns
- define contracts and boundaries
- review rollout and risk
- revise until interfaces and ownership are stable

### `TASK BREAKDOWN`

- split work into small tasks
- assign one repo per task
- add commands, done criteria, and ownership
- reject tasks that are too big or not autonomy-safe

### `IMPLEMENTATION`

**Execution modes:** `interactive`, `ralph-loop`, `fleet`, `manual`, or `fast-track`. Read from `workspace.yml` `mode` or `execution-plan.yaml` `execution.mode`.

- `interactive` — human initiates each step
- `ralph-loop` — pick highest-priority unblocked task, execute, update state, repeat
- `fleet` — parallel wave of disjoint tasks; merge outcomes between waves
- `manual` — human triggers each task individually; no autonomous scheduling
- `fast-track` — auto-chain planning phases into Ralph loop for trusted workstreams

**Task-level TDD loop** (one iteration per task):

```text
RED -> GREEN -> REFACTOR -> FULL SUITE
```

**Slice verification loop** (beta — advisory):

When the execution plan defines `slices[]`, the implementer runs a verification gate after completing all tasks in a slice before advancing:

```text
for each slice:
  execute tasks in slice (via task loop above)
  run slice.verification.commands
  if gate passes: advance to next slice
  if gate fails (degraded confidence):
    record in task board as deferred-verification
    report confidence level; do not silently advance
```

Verification may be skipped when the environment does not support it (e.g., no build runner). Mark affected tasks with `verification.confidence: degraded` and record a follow-up item in the task board.

**Review gate** — after all slices complete, the REVIEW phase runs as a separate gate before the feature is considered done. See REVIEW phase loop below.

### `REVIEW`

- invoke `/review-delta` or `/review-pr` for structural analysis (blast radius, affected flows, risk scoring)
- test correctness
- security and safety checks
- domain logic checks
- coding-style and regression checks
- send blockers back to implementation when needed

### `DISTILL`

- summarize what changed
- record reusable learnings
- update memory indexes
- note candidate improvements to Helix itself

**`/chronicle` (optional, experimental):** If the host runtime provides a `/chronicle` capability, its session-event log may be passed to the distiller as supplementary enrichment. Treat it as advisory only — learnings and decisions must be derived from workspace artifacts and code changes, not solely from the chronicle log. If `/chronicle` is unavailable or noisy, skip it without degrading distill quality.

## Beta Runtime Artifacts

The following artifacts are **beta / advisory**. They are machine-generated or operator-authored aids; agents should read them when present and continue without them when absent.

### `.helix/repo-capabilities/{repo-id}.yml`

Records discovered capability hints for one repo: language/build markers plus abstract verification layers. Generated by `setup-workspace.ps1` during workspace attach/refresh. Agents may read this to understand what kinds of proof a repo likely supports without re-inspecting it on every task.

Schema (minimal):

```yaml
schema_version: 1            # beta
repo_id: orders-api
local_path: workspaces/order-history/repos/orders-api
last_scanned_at: 2026-05-01T09:00:00Z
present: true
language_hints:
  primary: csharp
  detected: [csharp]
  confidence: medium
  notes: []
build_hints:
  systems: [dotnet]
  package_managers: [nuget]
  notes:
    - Manifest-driven detection. Actual commands live in repo docs and execution plans.
verification_layers:
  - layer: build
    execution_scope: local-runnable
    confidence: high
    evidence: [dotnet]
    trust_notes:
      - Manifest-driven detection. Actual build commands are configured per repo.
  - layer: unit
    execution_scope: local-runnable
    confidence: medium
    evidence: [directory:tests, file:Orders.Api.Tests.csproj]
    trust_notes:
      - Heuristic detection based on test naming conventions.
```

### `workspaces/{id}/verification-policy.yml`

Operator-authored policy for how slice verification gates are evaluated in this workspace. Optional. Opt in by declaring `artifacts.verification_policy` in `workspace.yml`. When absent, the implementer falls back to task-level `commands.verify`.

Schema (minimal):

```yaml
schema_version: 1            # beta
workspace_id: order-history
last_seeded_at: 2026-05-01T09:00:00Z
policy:
  mode: advisory
  trust_model: beta-heuristic
  default_requirements: [build, unit]
  optional_layers: [contract_sandbox, integration_acceptance, ui_e2e]
  slice_gates:
    default_gate: run-verify   # run-verify | skip | require-human
    on_degraded_confidence: defer-and-record   # defer-and-record | block | skip
  backpressure:
    max_consecutive_unverified_slices: 2
overrides: []
```

> These schemas are in beta. Fields may change. Do not treat them as stable contracts.

The process should prefer progressive disclosure over giant blobs.

- `refined-intent.md` should usually stay single-file and small
- `prd/` should be package-first when work spans multiple repos or many requirements
- `tech-design/` should be package-first when contracts, flows, or rollout details get large
- `execution-plan.yaml` stays machine-readable and single-file
- context bundles stay task-scoped

## Workspace Scope

A workspace or feature-space should declare the subset of repos it actually needs.

- `helix-repos.yml` is the canonical registry of repos Helix knows how to use (`repos.yml` remains the legacy compatibility alias)
- workspace manifest selects the repos participating in a feature
- repo readiness state is generated separately under `.helix/repo-state/`

That separation keeps setup deterministic:

1. know all repos
2. select participating repos
3. attach only the needed repos
4. onboard only the repos that need onboarding
5. run the lifecycle

## Document Roles

- `README.md`: human overview and bootstrap
- `AGENTS.md`: agent retrieval and source-of-truth map
- `.github/copilot-instructions.md`: short execution rules
- this document: full Helix process definition

## Current Direction

Helix is moving toward a split model:

- `helix-core` as the reusable source of truth for agents, prompts, skills, templates, and installer logic
- a meta repo as the installed coordination instance
- product repos attached from the registry only when needed

See [`helix-core-meta-repo-model.md`](./helix-core-meta-repo-model.md) for that structure.
