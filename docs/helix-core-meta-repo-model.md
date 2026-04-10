# Helix Core And Meta-Repo Model

This document describes the target packaging model for Helix.

The current repo still mixes reusable Helix assets with live-instance concerns. The target model separates those concerns so Helix is easier to install, copy, evolve, and use across projects.

## Goal

Split Helix into:

- `helix-core`: reusable source of truth
- meta repo: installed coordination instance
- product repos: attached working set

## Why Change

The current combined layout creates friction:

- copying Helix also copies instance-specific state
- active workspace paths and runtime-facing `.github` files are easy to misplace
- repo registry, repo state, and feature state are not cleanly separated
- core process documentation is spread across several files

## Target Model

### `helix-core`

Reusable source of truth for built-in Helix capabilities.

Owns:

- built-in agent definitions
- prompts
- skills
- templates
- installer and sync scripts
- canonical process docs

Does not own:

- active workspace state
- feature artifacts
- per-installation repo registry
- generated readiness results

### Meta Repo

The coordination repo that a team clones and commits.

Owns:

- installed runtime-facing `.github` files
- root `README.md` and `AGENTS.md`
- `repos.yml`
- `workspaces/`
- `.helix/` runtime tracking and generated state
- docs that explain the local instance

### Product Repos

Repos Helix coordinates but does not own.

Own:

- product code
- tests
- local repo conventions
- repo-local onboarding outputs

## Meta Repo Structure

```text
meta-repo/
├── .github/
│   ├── agents/
│   ├── prompts/
│   ├── skills/
│   └── copilot-instructions.md
├── .helix/
│   ├── install-state.yml
│   ├── active-workspace.yml
│   ├── repo-state/
│   └── generated/
├── docs/
│   ├── helix-process.md
│   └── ...
├── workspaces/
│   └── <workspace-id>/
├── AGENTS.md
├── README.md
└── repos.yml
```

## Ownership Boundaries

### `.github/`

Runtime surface for Copilot and VS Code.

Install from `helix-core`:

- `agents/`
- `prompts/`
- `skills/`
- `copilot-instructions.md`

### `.helix/`

Helix runtime tracking and generated state.

Keep here:

- installed version/source information
- active workspace pointer
- generated repo readiness state
- generated reports and inventories

Do not use `.helix/` for long-lived feature artifacts that humans work in daily.

### `repos.yml`

Operator-authored repo registry.

Should answer:

- what repos exist
- where they live
- how to clone or attach them
- what their default branches and roles are

Should not answer:

- whether a repo is currently onboarded
- whether it is healthy right now
- which feature is using it today

### `workspaces/`

Human-visible feature-space artifacts.

Each workspace should declare:

- participating repos
- current status
- phase artifacts
- task and execution outputs

This is where `JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL` lives.

## Installation Model

Start with an installer or sync script. Do not require a published plugin.

Recommended flow:

1. clone or create the meta repo
2. run Helix install from local `helix-core`
3. materialize managed files into `.github/`, root docs, and starter `.helix/`
4. populate `repos.yml`
5. create a workspace
6. attach only the repos that workspace needs
7. scan readiness and onboard missing repos

## Managed Vs Local Files

Managed by `helix-core` installer:

- `.github/agents/*`
- `.github/prompts/*`
- `.github/skills/*`
- `.github/copilot-instructions.md`
- starter `README.md`
- starter `AGENTS.md`
- canonical process docs

Local or instance-owned:

- `repos.yml`
- `.helix/repo-state/*`
- `.helix/generated/*`
- `workspaces/*`
- org- or project-specific docs

Track managed installs in `.helix/install-state.yml`.

## Plugin Relationship

Using GitHub Copilot CLI `plugin.json` for `helix-core` package metadata is still a good idea.

Use `plugin.json` for:

- package name
- version
- built-in agent paths
- skill paths
- hooks
- MCP config

Do not use `plugin.json` as the meta-repo installation state file. It does not model file ownership, sync status, or local generated state.

## Naming

No built-in agent prefix migration is required for this step.

Keep existing filenames and agent names for now. Differentiate managed Helix assets through installation structure and install-state tracking first. Revisit naming only after the installer model is stable.

## Current Schema Baseline

The target shapes for `repos.yml`, `workspace.yml`, and `.helix/install-state.yml` are defined in [`helix-instance-schemas.md`](./helix-instance-schemas.md).

## Immediate Next Step

The next implementation pass should focus on:

1. installer and sync behavior for managed files
2. `.helix/repo-state/<repo-id>.yml` shape
3. workspace setup and doctor commands against the new manifests
