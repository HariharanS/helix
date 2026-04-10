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
SETUP -> JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
```

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
- inspect repo readiness
- onboard only repos that are not Helix-ready
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

Task-level TDD loop:

```text
RED -> GREEN -> REFACTOR -> FULL SUITE
```

Scheduler loops:

- interactive loop: human reviews phase outputs and initiates next step
- Ralph loop: pick highest-priority safe task, execute, update state, repeat
- fleet loop: select disjoint safe tasks, run a parallel wave, merge outcomes, repeat

### `REVIEW`

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

## Artifact Shape

The process should prefer progressive disclosure over giant blobs.

- `refined-intent.md` should usually stay single-file and small
- `prd/` should be package-first when work spans multiple repos or many requirements
- `tech-design/` should be package-first when contracts, flows, or rollout details get large
- `execution-plan.yaml` stays machine-readable and single-file
- context bundles stay task-scoped

## Workspace Scope

A workspace or feature-space should declare the subset of repos it actually needs.

- `repos.yml` is the registry of repos Helix knows how to use
- workspace manifest selects the repos participating in a feature
- repo readiness state is generated separately from the registry

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
