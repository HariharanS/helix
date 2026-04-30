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
- installed Helix-managed docs, scripts, and templates under `helix/`
- root `README.md` and `AGENTS.md`
- `helix-repos.yml`
- `workspaces/`
- `.helix/` runtime tracking and generated state
- optional local docs that explain the instance

### Product Repos

Repos Helix coordinates but does not own.

Own:

- product code
- tests
- local repo conventions
- repo-local onboarding outputs

**Active workspace checkout location:** `workspace-setup.ps1` materializes the active working set under `workspaces/{workspace-id}/repos/{repo-id}/`.

> **Compatibility note:** existing `helix-repos.yml` `local_path` values remain instance-authored and may still point at older root-level or sibling checkouts until a dedicated migration exists. Keep parity with current runtime behavior; do not assume setup rewrites registry paths.

## Meta Repo Structure

```text
meta-repo/
├── .github/
│   ├── agents/
│   ├── hooks/
│   │   └── logs/
│   ├── prompts/
│   └── skills/
├── .helix/
│   ├── install-state.yml
│   ├── active-workspace.yml
│   ├── repo-state/
│   ├── repo-capabilities/          ← beta: generated per-repo capability cache
│   └── generated/
├── helix/
│   ├── docs/
│   │   ├── helix-core-meta-repo-model.md
│   │   ├── helix-process.md
│   │   └── helix-instance-schemas.md
│   ├── scripts/
│   └── templates/
├── workspaces/
│   └── <workspace-id>/
│       ├── workspace.yml
│       ├── verification-policy.yml ← beta: operator-authored verification gate policy
│       ├── repos/
│       │   └── <repo-id>/      ← active workspace checkouts
│       ├── task-boards/
│       ├── execution-plans/
│       ├── decisions/
│       └── <phase-artifacts>
├── <workspace-id>.code-workspace  ← generated at meta-repo root; gitignored
├── AGENTS.md
├── README.md
└── helix-repos.yml
```

## Ownership Boundaries

### `.github/`

Runtime surface for Copilot and VS Code.

Install from `helix-core`:

- `agents/`
- `hooks/` and live audit logs under `.github/hooks/logs/`
- `prompts/`
- `skills/`

Helix does not install `.github/copilot-instructions.md` or generated `.github/instructions/*.instructions.md` summaries. The default persistent instruction surface is root and nested `AGENTS.md`.

### `helix/`

Installed Helix-managed human-facing assets.

Keep here:

- canonical process docs
- installer, sync, and setup scripts
- artifact and manifest templates

Do not use `helix/` for workspace-specific task boards, decisions, or other feature artifacts.

### `.helix/`

Helix runtime tracking and generated state.

Keep here:

- installed version/source information
- active workspace pointer
- generated repo readiness state
- generated reports and inventories

Do not use `.helix/` for long-lived feature artifacts that humans work in daily.

### `helix-repos.yml`

Operator-authored repo registry. The canonical manifest name is `helix-repos.yml`.

> **Legacy:** `repos.yml` is retained as a compatibility alias for older instances. New instances should use `helix-repos.yml`.

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

Each workspace also owns its active repo checkouts under `workspaces/<id>/repos/<repo-id>/`.

A generated `<workspace-id>.code-workspace` file is placed at the **meta-repo root** (not inside the workspace folder) so VS Code can open the active workspace repos from one place.

Task boards and decisions are canonical inside `workspaces/<id>/...`, not at the meta-repo root.

This is where `JAM -> PRD -> TECH DESIGN -> TASK BREAKDOWN -> IMPLEMENTATION -> REVIEW -> DISTILL` lives.

## Installation Model

Start with an installer or sync script. Do not require a published plugin.

Recommended flow:

1. clone or create the meta repo
2. run Helix install from local `helix-core`
3. materialize managed files into `.github/`, `helix/`, and starter `.helix/`
4. populate `helix-repos.yml`
5. create a workspace
6. run workspace setup to clone or attach only the repos that workspace needs under `workspaces/<id>/repos/<repo-id>/`
7. scan readiness, generate `<workspace-id>.code-workspace` at the meta-repo root, and remove legacy Helix-generated `.github/instructions/*.instructions.md` summaries if present

> **One active workspace per session:** At any point exactly one workspace is active, tracked in `.helix/active-workspace.yml`. Switch workspaces explicitly; agents read this file to locate the correct artifact tree and active checkout paths.

## Managed Vs Local Files

Managed by `helix-core` installer:

- `.github/agents/*`
- `.github/hooks/*`
- `.github/prompts/*`
- `.github/skills/*`
- `helix/docs/*`
- `helix/scripts/*`
- `helix/templates/*`
- starter `README.md`
- starter `AGENTS.md`

Local or instance-owned:

- `helix-repos.yml` — canonical repo registry (`repos.yml` kept as legacy compatibility alias)
- `.helix/repo-state/*`
- `.helix/repo-capabilities/*` — beta: generated per-repo capability cache (gitignored or committed per preference)
- `.helix/generated/*`
- `workspaces/*`
- `workspaces/<id>/verification-policy.yml` — beta: operator-authored slice verification policy (optional)
- `workspaces/<id>/repos/<repo-id>/` — active workspace product repo checkouts (gitignored)
- `<workspace-id>.code-workspace` — generated VS Code workspace file at the meta-repo root (gitignored)
- org- or project-specific docs
- any legacy root `decisions/` or `task-boards/` directories until they are manually removed

Track managed installs in `.helix/install-state.yml`.

## Upstreaming Changes From An Installed Meta Repo

When a useful Helix change is first discovered inside an installed meta repo, do not blindly copy the edited file back to `helix-core`. First classify the change by ownership:

| If the local change is in... | It usually means... | Upstream in `helix-core` by changing... | Typical rollout |
|---|---|---|---|
| `.github/agents/*`, `.github/skills/*`, `AGENTS.md`, `helix/docs/*` | a managed runtime or documentation source file changed | the same source file path in `helix-core` | fresh installs + `sync-helix` |
| `helix/templates/*` | the default shape for new installs should change | the template file | fresh installs only unless a migration is added |
| `.helix/*` | instance state or instance config changed | usually **not** the same file; instead update a template or script if the behavior should become a default | depends on migration strategy |
| behavior emitted during install, sync, or workspace setup | the generator/runtime logic is wrong or incomplete | `helix/scripts/*` plus any affected docs/templates | fresh installs, and existing installs after rerunning the script |

Use this rule of thumb:

1. **Managed source file** -> upstream the same path in `helix-core`
2. **Default for new installs** -> upstream the template
3. **Automatic emission or regeneration** -> upstream the script/generator
4. **Instance-only state** -> keep local unless you intentionally add a migration path

### Worked Example: CRG Review Skills

Suppose an installed meta repo adds:

- `.github/skills/build-graph/SKILL.md`
- `.github/skills/review-delta/SKILL.md`
- `.github/skills/review-pr/SKILL.md`

and updates:

- `.github/agents/helix.agent.md`
- `.github/agents/reviewer.agent.md`
- `helix/docs/helix-process.md`
- `helix/docs/cli-workflow.md`

Those are all **managed source** edits. The upstream move is to add or update the same files in `helix-core`, then rely on the installer/sync path to materialize them into meta repos.

If the same CRG work also changes `.helix/context-providers.yml` to explain valid modes better, that file should **not** be copied back as-is. The upstream change belongs in `helix/templates/context-providers.yml.template`, because the instance file is seeded from a template and then becomes instance-owned.

If later we decide existing installs should also be corrected automatically, that becomes a **script** change: update the relevant installer or sync logic in `helix/scripts/*` to migrate old instances.

### Recommended Upstream Order

When a change spans more than one ownership bucket, upstream in this order:

1. **Source files** - agents, skills, docs, instructions
2. **Templates** - default config or starter artifact shape
3. **Scripts/generators** - only when installs, sync, or setup should emit or migrate behavior automatically

Before merging, decide the rollout policy explicitly:

- **fresh installs only**
- **fresh installs + `sync-helix`**
- **explicit migration for existing instances**

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

The target shapes for `helix-repos.yml`, `workspace.yml`, and `.helix/install-state.yml` are defined in [`helix-instance-schemas.md`](./helix-instance-schemas.md).

## Immediate Next Step

The next implementation pass should focus on:

1. smoke-testing install and setup against a real meta repo plus attached product repos
2. continuing to converge the wrapper scripts (`helix init|sync|upgrade|workspace setup`) onto the future unified CLI while keeping the underlying compatibility shims stable
3. fully retiring or migrating the remaining legacy combined-layout examples and helpers
