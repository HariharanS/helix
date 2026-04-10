# Helix

Helix is a workspace-first orchestration system for AI-driven development across multiple repos.

This repo currently contains the reusable Helix assets and the working design for how Helix should install into a meta repo. Product code still lives outside Helix.

## What Helix Is For

- Coordinating multi-repo feature delivery
- Running staged AI-assisted workflows from vague idea to reviewed implementation
- Keeping planning, design, task breakdown, and memory outside product repos
- Providing reusable agents, skills, prompts, and context-passing conventions

## What Helix Does Not Own

- Product source code in sibling service repos
- Product deployment infrastructure for those repos
- Raw session transcripts as long-term state

## Human Docs vs Agent Docs

- `README.md` is human-first: overview, workflow, architecture, and entry points
- `AGENTS.md` files are agent-first: navigation, source-of-truth rules, and retrieval guidance
- `docs/` holds longer guides and roadmap material

If you are an agent, start with [`AGENTS.md`](./AGENTS.md), not this file.

## System Architecture

```mermaid
graph TD
    Human[Developer] --> Helix[Helix Orchestrator]

    subgraph "Reasoning Tier (Opus)"
        Jam[Jam]
        Planner[Planner]
        Architect[Architect]
    end

    subgraph "Analysis Tier (Sonnet)"
        Decomposer[Decomposer]
        Reviewer[Reviewer]
    end

    subgraph "Coding Tier (Codex)"
        Implementer[Implementer]
        TDDRed[TDD-Red]
    end

    subgraph "Fast Tier (Haiku)"
        Explorer[Explorer]
        Scribe[Scribe]
        Distiller[Distiller]
        Resume[Resume]
    end

    subgraph "Visual Tier (Gemini)"
        UITester[UI-Tester]
    end

    Helix --> Jam & Planner & Architect & Decomposer
    Helix --> Explorer & TDDRed & Implementer & Reviewer
    Helix --> Scribe & Distiller & Resume & UITester
    Explorer --> SubExplorer[Sub-Explorer per repo]
    TDDRed --> Implementer
    Implementer --> Explorer
```

## Lifecycle

Helix runs a staged delivery flow:

```text
SETUP -> JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL
```

The full lifecycle, loops, and artifact rules are defined in [`docs/helix-process.md`](./docs/helix-process.md).

## Execution Modes

| Mode | Mechanism | Use Case |
|------|-----------|----------|
| `interactive` | Handoffs between phase owners | New features, risky work, human-in-the-loop delivery |
| `fast-track` | Auto-chain planning phases into Ralph loop | Trusted work where phase outputs are already solid |
| `ralph-loop` | Highest-priority unblocked task, commit, repeat | Default autonomous implementation mode |
| `fleet` | Parallel implementers on disjoint tasks | Independent tasks with locked contracts and non-overlapping ownership |

## Agent Roster

| Agent | Tier | Purpose |
|------|------|---------|
| `helix` | analysis | Pure dispatcher and phase router |
| `jam` | reasoning | Clarifies intent |
| `planner` | reasoning | Produces PRD |
| `architect` | reasoning | Produces technical design |
| `decomposer` | analysis | Produces task board and execution plan |
| `explorer` | fast | Gathers evidence-backed context |
| `tdd-red` | coding | Writes failing tests |
| `implementer` | coding | Implements tasks through TDD |
| `reviewer` | analysis | Runs multi-lens review |
| `scribe` | fast | Updates task boards and decisions |
| `distiller` | fast | Writes memory and learnings |
| `resume` | fast | Reconstructs session state |
| `ui-tester` | visual | Playwright and UI verification |

## Repository Layout

```text
helix/
├── README.md
├── AGENTS.md
├── .github/      # agent definitions, skills, prompts, global instructions
├── .helix/       # active workspace, model config, memory
├── workspaces/   # workspace-scoped artifacts and bundles
├── docs/         # human-facing guides and roadmap
├── templates/    # artifact templates and examples
├── scripts/      # helper scripts and lifecycle hooks
├── hooks/        # hook configuration
├── decisions/    # legacy placeholder, not canonical workspace state
└── task-boards/  # legacy placeholder, not canonical workspace state
```

## Workspace Model

Workspace-scoped artifacts are the source of truth for feature delivery:

```text
workspaces/{name}/
├── workspace.yml
├── refined-intent.md
├── prd.md or prd/
├── tech-design.md or tech-design/
├── task-boards/
├── execution-plans/
├── decisions/
└── context-bundle-*.md
```

Principles:

- Workspace artifacts stay in Helix
- Product code changes stay in sibling repos
- Execution plans are the machine-readable source of truth for automation
- Context bundles are task-scoped evidence, not general documentation
- If an artifact grows too large, prefer an `index.md` plus annexes or subdocuments over a single blob

## Target Deployment Model

Helix is moving toward:

- `helix-core` as the reusable source of truth
- a meta repo as the installed coordination instance
- attached product repos selected through `repos.yml`

The target packaging and installation model is defined in [`docs/helix-core-meta-repo-model.md`](./docs/helix-core-meta-repo-model.md).
The target meta-repo manifest shapes are defined in [`docs/helix-instance-schemas.md`](./docs/helix-instance-schemas.md).

Current runtime tooling in this repo:

- `scripts/install-helix.ps1` — install or sync managed Helix files into a meta repo
- `scripts/setup-workspace.ps1` — attach selected repos and activate a workspace
- `scripts/doctor.ps1` — validate manifests and refresh repo-state
- `scripts/sync-helix.ps1` — re-sync an installed meta repo from its recorded Helix core source

## Where To Start

- New to Helix: [`docs/starting-cross-repo-feature-with-helix.md`](./docs/starting-cross-repo-feature-with-helix.md)
- Canonical lifecycle and loops: [`docs/helix-process.md`](./docs/helix-process.md)
- Core vs meta-repo model: [`docs/helix-core-meta-repo-model.md`](./docs/helix-core-meta-repo-model.md)
- Meta-repo manifest schemas: [`docs/helix-instance-schemas.md`](./docs/helix-instance-schemas.md)
- Future platform direction: [`docs/helix-platform-roadmap.md`](./docs/helix-platform-roadmap.md)
- Agent navigation and source-of-truth rules: [`AGENTS.md`](./AGENTS.md)

## Optional Copilot Rubber Duck

When running inside GitHub Copilot CLI experimental mode, Helix can use Rubber Duck as an optional second opinion at high-return checkpoints.

- Best checkpoints: after PRD, after design, after task breakdown, after complex implementation, after writing tests, and when stuck
- Treat the critique as advisory
- If it changes scope, design, or task safety, route back to the right phase and update workspace artifacts
- If it is unavailable, continue the normal Helix flow
