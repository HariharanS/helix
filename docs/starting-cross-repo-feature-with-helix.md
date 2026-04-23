# Starting A Cross-Repo Feature With Helix

See also: [Helix Platform Roadmap](./helix-platform-roadmap.md)

This guide is for the case where:

- you have multiple existing repos
- those repos do not yet have AI-specific context
- you want to deliver one feature across them
- you want to use TDD for unit tests
- you already have sandboxed integration tests
- you already have Playwright UI tests

## What Helix Is Doing

Helix is a meta-repo. It does not own the product code.

- Workspace artifacts live in Helix
- Code changes live in the individual service repos
- Helix coordinates a staged lifecycle: SETUP -> JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
- The important part is not just the phases but the loops inside them: clarify until intent is unambiguous, design until contracts are locked, decompose until the execution plan is runnable, then execute through TDD plus Ralph loop or fleet scheduling

## Lifecycle At A Glance

For a first cross-repo feature, think about Helix like this:

```text
SETUP -> JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
```

The main loops inside that lifecycle are:

- **Setup loop** — sync repos -> onboard or refresh repo context -> verify active workspace
- **JAM loop** — restate intent -> ask one clarifying question -> tighten scope -> repeat
- **Design loop** — inspect patterns -> define contracts and boundaries -> review -> revise
- **Task loop** — split tasks -> add commands and ownership -> check autonomy gates -> resize or repair
- **Implementation loops** — task-level TDD (`RED -> GREEN -> REFACTOR -> FULL SUITE`) inside Ralph loop or fleet scheduling
- **Review loop** — run security, correctness, domain, style, and test lenses independently

## Recommended Starting Mode

For your first feature, use **interactive mode**, not fast-track or fleet.

Why:

- your repos are not onboarded yet
- Helix needs to discover each repo's structure and test conventions
- cross-repo contract boundaries need to be made explicit before autonomous implementation is safe

Move to Ralph loop or fleet only after:

- each repo has been onboarded
- the contract between repos is locked
- the execution plan has repo-scoped tasks with verified commands and ownership

## Optional Second-Opinion Checkpoints

If your Copilot runtime provides an optional second-opinion critique capability, you can ask for a critique at the stage boundaries where a second opinion has the highest return.

Use it sparingly:

- after PRD, if requirements still feel ambiguous or risky
- after tech design, before task breakdown, if contracts or rollout paths feel fragile
- after task breakdown, before Ralph loop or fleet, if ownership or commands may be unsafe
- after a complex implementation, if the change spans multiple files or boundaries
- after writing tests, before relying on them as proof
- whenever the current agent is stuck or looping

Treat the critique as advisory only. If it changes the shape of the work, move back to the right phase and update the workspace artifacts.

## Phase 0: SETUP — Create And Sync The Workspace

Before you ask Helix to plan or code, bootstrap the meta repo and create a workspace for the feature.

### 0a. Bootstrap The Meta Repo

Run the bootstrap command from `helix-core` into the target meta-repo root:

```powershell
./scripts/init-meta-repo.ps1 -TargetRoot C:/path/to/meta-repo
```

That should install or sync Helix into the target root and verify the baseline install state, including `.helix/install-state.yml`, the managed `.github/` runtime files, and the starter manifests.

After bootstrap, the installed Helix-managed docs, scripts, and templates live under `helix/` inside the target meta repo.

### 0b. Author The Registry And Workspace Manifests

After bootstrap:

- update `repos.yml` with the real repo registry for your environment
- create or update `workspaces/{name}/workspace.yml` for the subset of repos this feature-space needs

Keep `repos.yml` declarative. Defining the registry should not clone every repo. Cloning or attaching happens only when the workspace is set up.

The target meta-repo model uses:

- `repos.yml` for the full repo registry
- `workspaces/{name}/workspace.yml` for the subset of repos this feature-space needs
- `.helix/repo-state/*.yml` for generated readiness status

Example registry file: `repos.yml`

```yaml
schema_version: 1
repos:
  - id: orders-api
    remote: https://github.com/your-org/orders-api
    local_path: ../orders-api
    default_branch: main
  - id: orders-web
    remote: https://github.com/your-org/orders-web
    local_path: ../orders-web
    default_branch: main
  - id: customer-profile-adapter
    remote: https://github.com/your-org/customer-profile-adapter
    local_path: ../customer-profile-adapter
    default_branch: main
```

Example workspace file: `workspaces/order-history/workspace.yml`

```yaml
schema_version: 1
id: order-history
description: Order history feature spanning api, web, and downstream adapter repos
status: active
mode: interactive
repos:
  - repo_id: orders-api
    role: primary
    branch: main
  - repo_id: orders-web
    role: primary
    branch: main
  - repo_id: customer-profile-adapter
    role: dependency
    branch: main

artifacts:
  refined_intent: refined-intent.md
  prd: prd/index.md
  tech_design: tech-design/index.md
  task_board_dir: task-boards/
  execution_plan_dir: execution-plans/
  decisions_dir: decisions/
```

Keep task boards and decisions inside each workspace. Root `decisions/` and `task-boards/` directories are deprecated legacy placeholders, not the active model.

Then use the `setup` agent, the `workspace-sync` skill, or the installed `helix/scripts/setup-workspace.ps1` command to:

- clone or attach only the selected repos
- generate or refresh `.helix/repo-state/*.yml`
- generate the workspace file
- update additional directories
- set `.helix/active-workspace.yml`

Use the legacy Bash helper only for the old combined layout. The PowerShell script is the target entry point for the meta-repo model.

### Optional: Enable Graph Retrieval Conservatively

If you want structural code retrieval without making it mandatory, enable `code-review-graph` in `mcp` mode only after the graph is built:

```powershell
./helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode mcp
```

That keeps Helix in charge of process and workspace artifacts while using the graph for targeted structural retrieval when it is actually available.

If it is noisy, unhelpful, or too expensive, turn it back off:

```powershell
./helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode off
```

### Setup Loop: Onboard Every Repo

Because some repos may not be Helix-ready yet, onboarding is the first real step for only the repos that need it.

Use `.helix/repo-state/{repo-id}.yml` to decide which repos need onboarding. Run the `onboard` skill only for repos marked `needs-onboarding` or `partial`.

The goal is to generate repo-specific context from the actual codebase:

- root `AGENTS.md`
- source-level `AGENTS.md`
- `.github/instructions/*.instructions.md`
- repo-specific skills where patterns are strong enough

This matters because Helix is designed to **discover** conventions instead of guessing them.

For your setup, onboarding should specifically capture:

- unit test frameworks and naming patterns in each repo
- integration test layout and how sandbox mode is wired
- Playwright conventions in the UI repo
- how service contracts are defined today
- any existing mocking, fixture, or fake downstream patterns

Do not skip this. If onboarding is weak, the later TDD and implementation phases will be noisy and error-prone.

The SETUP phase is complete only when:

- the workspace exists
- the active workspace pointer is correct
- each repo is attached or cloned
- each repo has usable AI context from onboarding

## Phase 1: JAM — Refine The Feature Before Planning

Start with JAM if the feature is still partly vague.

Use a prompt like:

```text
@helix Start a new feature in the active workspace.
The feature spans orders-api, orders-web, and customer-profile-adapter.
We have no previous AI context in these repos.
Use JAM first and make the downstream contract changes explicit.
Testing requirements:
- unit tests first in each repo
- sandbox integration tests for service-to-service behavior
- Playwright coverage for the UI flow
```

The JAM phase should clarify:

- what user problem is being solved
- which repos are affected and why
- where the source of truth lives
- what the cross-repo contract is
- what is in scope vs out of scope

Output goes to `workspaces/{name}/refined-intent.md`.

This phase is a loop, not a single prompt:

- restate the feature
- ask one clarifying question at a time
- inspect the codebase if needed
- narrow scope until the feature is specific enough to plan cleanly

## Phase 2: PRD — Produce The Requirements

Once the feature intent is clear, ask Helix to move to PRD.

The PRD should answer:

- user-facing behavior
- business rules
- non-functional constraints
- error and empty-state behavior
- acceptance criteria at the feature level

For a cross-repo feature, the PRD should also name:

- the owning repo for each behavior
- contract dependencies between repos
- which behaviors must be proven by unit, integration, and UI tests

Output goes to `workspaces/{name}/prd.md`.

For cross-repo or larger features, prefer a PRD package instead:

- `workspaces/{name}/prd/index.md`
- `workspaces/{name}/prd/user-stories.md`
- `workspaces/{name}/prd/requirements.md`
- `workspaces/{name}/prd/repo-ownership.md`
- `workspaces/{name}/prd/risks-and-open-questions.md`

Keep `index.md` short and use it as the read entry point.

The PRD loop is:

- gather domain evidence
- draft requirements
- surface gaps or conflicts
- revise until the requirements are concrete and testable

## Phase 3: TECH DESIGN — Lock The Contracts

This is the most important phase for cross-repo delivery.

Your tech design should make these things explicit:

- request and response contracts between repos
- ownership of domain logic vs orchestration vs UI
- where sandbox integration coverage sits
- which repo exposes the contract and which repo consumes it
- rollout or compatibility constraints if one repo ships before another

Use the design to decide the test layers:

- **Unit tests** prove repo-local business logic and adapters
- **Sandbox integration tests** prove repo-to-repo contracts without real downstream APIs
- **Playwright tests** prove the end-user flow across the UI

Output goes to `workspaces/{name}/tech-design.md`.

For cross-repo or larger features, prefer a design package instead:

- `workspaces/{name}/tech-design/index.md`
- `workspaces/{name}/tech-design/contracts.md`
- `workspaces/{name}/tech-design/domain-model.md`
- `workspaces/{name}/tech-design/execution-flow.md`
- `workspaces/{name}/tech-design/rollout-and-risks.md`

Keep `index.md` short and use it as the read entry point.

The design loop is:

- inspect existing patterns
- define contracts and repo boundaries
- review with the user
- revise until ownership and interfaces are locked

## Phase 4: TASK BREAKDOWN — Build The Execution Plan

Helix expects cross-repo work to be split into **one repo per task**.

Do not create a task like "implement order history everywhere".

Instead, decompose it into tasks such as:

- TASK-001: define API contract in `orders-api`
- TASK-002: implement domain logic in `orders-api`
- TASK-003: adapt sandbox integration coverage in `orders-api`
- TASK-004: consume new contract in `orders-web`
- TASK-005: add Playwright scenario in `orders-web`
- TASK-006: update adapter behavior in `customer-profile-adapter`

The decomposer should produce both:

- `workspaces/{name}/task-boards/{feature}.md`
- `workspaces/{name}/execution-plans/{feature}.yaml`

The execution plan is what makes implementation safe. Every task should include:

- `repo`
- `context_bundle`
- `ownership.write_paths`
- `commands.focused_test`
- `commands.full_suite`
- `done_when`

If any of those are missing, keep the task in interactive mode and do not send it to autonomous execution.

This phase is complete only when the execution plan is runnable:

- each task is repo-scoped
- each task has clear acceptance criteria
- commands are verified
- write ownership is explicit
- tasks are marked correctly for interactive, Ralph loop, or fleet execution

## Phase 5: IMPLEMENTATION — Run TDD Plus Scheduler Loops

For each task, Helix should use the TDD cycle.

The default shape is:

1. read the task and acceptance criteria
2. read the repo's `AGENTS.md` and instructions
3. write failing tests first
4. run the focused tests and confirm they fail
5. write the minimum implementation
6. rerun the focused tests until green
7. refactor only within the task's scope
8. run the full suite for that repo

Helix implementation also has an outer scheduler loop:

- **Ralph loop** — pick the highest-priority unblocked task, execute it, record the result, then recompute the next task
- **Fleet loop** — select tasks with disjoint write ownership, run them in parallel, collect results, then schedule the next wave

The implementation phase is done per task only when:

- focused tests pass
- the repo-level suite has been run
- `done_when` is satisfied
- blockers are reported instead of guessed around

### How To Apply TDD In Your Setup

Use the test layers deliberately.

**Unit tests**

- Add or update them inside the repo that owns the logic
- These should be the first failing tests for most implementation tasks
- Prefer focused commands in the execution plan for fast red-green loops

**Sandbox integration tests**

- Add or update them when a repo boundary or downstream contract is involved
- Keep them in sandbox mode so they prove orchestration and translation logic without real downstream calls
- Treat these as contract-verification tests, not substitutes for unit tests

**Playwright UI tests**

- Add them after backend and contract tasks are stable enough for the flow to be meaningful
- Use them to prove the main user journey and key visible edge states
- Keep them narrow; do not force Playwright to cover every business rule already proven below the UI

## Phase 6: REVIEW — Apply The Quality Gate

Before you treat the feature as ready, run Helix review as a separate phase.

The review loop is:

- security
- correctness
- domain logic
- coding style
- test coverage

If review finds blocking issues, route the work back to implementation and re-run review after the fixes.

## Phase 7: DISTILL — Capture Learnings

After review, distill the session into memory.

The distill loop is:

- summarize what happened
- capture key decisions and blockers
- extract reusable learnings
- identify candidate skills
- update the memory index

## A Good Order For Your First Cross-Repo Implementation

Use this sequence:

1. create or activate the workspace
2. sync the repos into the workspace
3. onboard all repos
4. confirm the SETUP phase is actually complete
5. JAM the feature
6. create the PRD
7. produce the tech design
8. decompose into repo-scoped tasks
9. implement contract tasks first
10. implement repo-local domain tasks with unit-test-first TDD
11. add or update sandbox integration tests around repo boundaries
12. add or update Playwright coverage for the user journey
13. run review
14. distill learnings into memory

That order reduces churn because UI and downstream consumers are not guessing against a moving contract.

## Suggested Prompt Sequence

You can drive the first run with prompts like these.

### 1. Start the workspace

```text
I want to start a new workspace called order-history.
It spans orders-api, orders-web, and customer-profile-adapter.
Set this up for Helix and onboard each repo.
```

### 2. Refine the feature

```text
@helix Start JAM for the order-history workspace.
I want a new feature that lets users view their historical orders in the web app.
The data comes from orders-api and may require adapter changes.
We need unit tests first, sandbox integration tests for downstream behavior, and Playwright coverage for the UI flow.
```

### 3. Move to PRD

```text
@helix Use the refined intent and produce the PRD for this feature.
Make the acceptance criteria explicit and identify which repos own which behaviors.
```

Optional second opinion:

```text
Critique this PRD before we move to design.
Focus on hidden assumptions, ambiguous acceptance criteria, and missing repo-boundary behavior.
```

### 4. Move to tech design

```text
@helix Create the technical design for this feature.
Lock the contracts between repos and define where unit, sandbox integration, and Playwright tests belong.
```

Optional second opinion:

```text
Critique this tech design before task breakdown.
Focus on contract stability, rollout risk, cross-repo edge cases, and unnecessary complexity.
```

### 5. Break the work down

```text
@helix Break this feature into repo-scoped tasks and create the execution plan.
Do not create cross-repo implementation tasks.
Verify focused and full test commands per repo.
```

Optional second opinion:

```text
Critique this execution plan before autonomous implementation.
Focus on missing commands, overlapping write ownership, unsafe parallelism, and weak done criteria.
```

### 6. Start implementation

```text
@helix Start implementation in interactive mode.
Use TDD for each task.
Begin with the first contract task, then move to the next unblocked task.
```

### 7. Review the result

```text
@reviewer Review the completed feature across the affected repos.
Focus on correctness, contract compatibility, test coverage, and scope control.
```

### 8. Distill learnings

```text
@distiller Capture learnings from this cross-repo feature, especially:
- onboarding gaps
- repeated sandbox integration patterns
- Playwright patterns worth standardizing
- repo-specific testing conventions that should be remembered
```

## How To Decide Between Interactive, Ralph, And Fleet

Use **interactive** when:

- this is the first time a repo is touched by Helix
- the task is ambiguous
- the contract is still moving
- test commands are not yet verified

Use **Ralph loop** when:

- the execution plan is complete
- tasks have clear commands and ownership
- you want Helix to keep picking the next safe task

Use **fleet** only when:

- tasks are truly independent
- write paths do not overlap
- shared contracts are already locked

For your first feature, the normal pattern should be:

- interactive through SETUP, JAM, design, and decomposition
- possibly Ralph for implementation later
- fleet only after you trust the task quality

## What "Done" Looks Like

For a well-run Helix feature, you should end with:

- onboarded repos with AI-readable conventions
- a workspace containing refined intent, PRD, tech design, task board, and execution plan
- repo-scoped commits in the actual product repos
- unit tests added through TDD in each affected repo
- sandbox integration tests covering contract boundaries
- Playwright coverage for the main user-visible flow
- a review artifact
- distilled learnings in Helix memory

## Common Mistakes To Avoid

- skipping onboarding and asking Helix to code immediately
- creating cross-repo tasks instead of repo-scoped tasks
- using Playwright to prove behavior that should have been covered by unit or sandbox integration tests
- moving to fleet mode before contracts and ownership are explicit
- leaving test commands vague in the execution plan
- letting integration tests call real downstream systems when the agreed safety model is sandbox mode

## Short Version

If you are starting from zero, the practical sequence is:

1. complete SETUP: create a Helix workspace, sync repos, and onboard every repo
2. JAM the feature
3. create the PRD
4. create the tech design
5. decompose into one-repo-per-task execution contracts
6. implement each task with TDD
7. verify repo boundaries with sandbox integration tests
8. verify the user flow with Playwright
9. review and distill

That is the cleanest way to introduce Helix into an existing multi-repo system without losing control of quality or scope.
