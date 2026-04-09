# Starting A Cross-Repo Feature With Helix

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
- Helix coordinates the phases: JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL

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

## Phase 0: Create A Workspace First

Before you ask Helix to plan or code, create a workspace for the feature.

Example file: `helix/workspaces/order-history/workspace.yaml`

```yaml
name: order-history
description: Order history feature spanning api, web, and downstream adapter repos
status: created
created: 2026-04-09
repos:
  - path: ../orders-api
    url: https://github.com/your-org/orders-api
    branch: main
    role: primary
    onboarded: false
  - path: ../orders-web
    url: https://github.com/your-org/orders-web
    branch: main
    role: primary
    onboarded: false
  - path: ../customer-profile-adapter
    url: https://github.com/your-org/customer-profile-adapter
    branch: main
    role: dependency
    onboarded: false
```

Then use the `workspace-sync` skill to:

- clone or attach the repos
- generate the workspace file
- update additional directories
- set `.helix/active-workspace.yaml`

There is also a helper script at [setup-workspace.sh](C:\Users\Harih\source\personal\github-copilot-multi-agent-setup\helix\scripts\setup-workspace.sh), but it is a Bash script, so the skill is the better default entry point.

## Phase 1: Onboard Every Repo

Because these repos have not used AI before, onboarding is the first real step.

Use the `onboard` skill on each repo in the workspace.

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

## Phase 2: Jam The Feature Before Planning

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

## Phase 3: Produce The PRD

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

## Phase 4: Lock The Technical Design

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

## Phase 5: Break The Feature Into Repo-Scoped Tasks

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

## Phase 6: Implement With TDD

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

## A Good Order For Your First Cross-Repo Implementation

Use this sequence:

1. onboard all repos
2. JAM the feature
3. create the PRD
4. produce the tech design
5. decompose into repo-scoped tasks
6. implement contract tasks first
7. implement repo-local domain tasks with unit-test-first TDD
8. add or update sandbox integration tests around repo boundaries
9. add or update Playwright coverage for the user journey
10. run review
11. distill learnings into memory

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

### 4. Move to tech design

```text
@helix Create the technical design for this feature.
Lock the contracts between repos and define where unit, sandbox integration, and Playwright tests belong.
```

### 5. Break the work down

```text
@helix Break this feature into repo-scoped tasks and create the execution plan.
Do not create cross-repo implementation tasks.
Verify focused and full test commands per repo.
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

- interactive through design and decomposition
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

1. create a Helix workspace
2. onboard every repo
3. JAM the feature
4. create the PRD
5. create the tech design
6. decompose into one-repo-per-task execution contracts
7. implement each task with TDD
8. verify repo boundaries with sandbox integration tests
9. verify the user flow with Playwright
10. review and distill

That is the cleanest way to introduce Helix into an existing multi-repo system without losing control of quality or scope.
