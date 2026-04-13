# Helix Instance Schemas

This document defines the target meta-repo manifest shapes for Helix.

These schemas are for the installed coordination instance, not for `helix-core` source files.

## Naming Note

Target-state meta-repo manifests use `.yml`:

- `repos.yml`
- `workspaces/<id>/workspace.yml`
- `.helix/install-state.yml`
- `.helix/active-workspace.yml`

The current combined Helix repo still contains some legacy `*.yaml` files from the pre-split layout. Treat those as legacy until the installer/runtime migration lands.

## Design Rules

- operator-authored manifests should stay compact and hand-editable
- generated state should live under `.helix/`
- registry data and runtime state must stay separate
- workspace manifests should reference repo ids, not duplicate repo registry details
- artifact entry paths should be explicit so agents do not need broad scans
- workspace artifact directories must stay under the workspace root; do not point them at legacy root `decisions/` or `task-boards/` folders

## `repos.yml`

Purpose: declare the full registry of repos Helix knows how to attach or clone.

Do use it for:

- repo ids
- clone remotes
- local paths
- default branches
- stable tags or notes

Do not use it for:

- readiness or onboarding status
- last scan timestamps
- active feature participation

### Schema

| Field | Required | Type | Notes |
|------|----------|------|------|
| `schema_version` | yes | integer | Start with `1` |
| `defaults` | no | map | Shared defaults applied when a repo omits a field |
| `defaults.default_branch` | no | string | Usually `main` or `master` |
| `defaults.clone_root` | no | string | Optional default base path such as `../` or `repos/` |
| `repos` | yes | list | Stable repo registry |
| `repos[].id` | yes | string | Stable identifier used by workspaces |
| `repos[].description` | no | string | Short human description |
| `repos[].remote` | yes | string | Git remote URL |
| `repos[].local_path` | yes | string | Relative checkout path from the meta-repo root |
| `repos[].default_branch` | no | string | Overrides `defaults.default_branch` |
| `repos[].default_role` | no | string | Optional hint such as `primary`, `dependency`, `supporting` |
| `repos[].tags` | no | list[string] | Stable classification tags |
| `repos[].disabled` | no | boolean | Exclude from normal setup without deleting the entry |
| `repos[].notes` | no | string | Small operator note |

### Example

```yaml
schema_version: 1

defaults:
  default_branch: main

repos:
  - id: orders-api
    description: Order API service
    remote: https://github.com/acme/orders-api
    local_path: ../orders-api
    default_role: primary
    tags: [backend, api]

  - id: orders-web
    description: Customer-facing web frontend
    remote: https://github.com/acme/orders-web
    local_path: ../orders-web
    default_role: primary
    tags: [frontend, web]

  - id: customer-profile-adapter
    description: Downstream adapter for customer profile reads
    remote: https://github.com/acme/customer-profile-adapter
    local_path: ../customer-profile-adapter
    default_role: dependency
    tags: [adapter, dependency]
```

### Validation Rules

- `id` must be unique
- `local_path` should be unique
- `remote` should be present even if the repo is already cloned locally
- `local_path` should resolve from the meta-repo root, not from a workspace folder
- no readiness fields such as `onboarded`, `ready`, or `last_scanned`

## `workspace.yml`

Purpose: declare one feature-space or project workspace and the subset of repos it uses.

Do use it for:

- workspace identity and status
- participating repo ids
- workspace-level branch overrides
- current phase
- artifact entry paths

Do not use it for:

- full clone metadata already present in `repos.yml`
- generated readiness scans
- giant narrative content that belongs in phase artifacts

### Schema

| Field | Required | Type | Notes |
|------|----------|------|------|
| `schema_version` | yes | integer | Start with `1` |
| `id` | yes | string | Stable workspace identifier, usually folder name |
| `display_name` | no | string | Human-friendly title |
| `description` | yes | string | Short summary of the feature-space |
| `status` | yes | string | `draft`, `active`, `blocked`, `done`, or `archived` |
| `mode` | no | string | `interactive`, `fast-track`, `ralph-loop`, or `fleet` |
| `objective` | no | string | One-sentence desired outcome |
| `created_at` | no | string | ISO date |
| `phase` | no | map | Current lifecycle position |
| `phase.current` | no | string | `setup`, `jam`, `prd`, `tech-design`, `task-breakdown`, `implementation`, `review`, `distill` |
| `phase.last_completed` | no | string | Most recently completed phase |
| `repos` | yes | list | Participating repos only |
| `repos[].repo_id` | yes | string | Must exist in `repos.yml` |
| `repos[].role` | yes | string | Workspace-specific role such as `primary`, `dependency`, `supporting` |
| `repos[].branch` | no | string | Workspace-specific branch override |
| `repos[].focus_areas` | no | list[string] | Optional repo-relative paths or domains of immediate interest |
| `artifacts` | yes | map | Entry points for downstream agents |
| `artifacts.refined_intent` | no | string | Workspace-relative path, usually `refined-intent.md` |
| `artifacts.prd` | no | string | Workspace-relative path, `prd.md` or `prd/index.md` |
| `artifacts.tech_design` | no | string | Workspace-relative path, `tech-design.md` or `tech-design/index.md` |
| `artifacts.task_board_dir` | yes | string | Workspace-relative dir, usually `task-boards/` |
| `artifacts.execution_plan_dir` | yes | string | Workspace-relative dir, usually `execution-plans/` |
| `artifacts.decisions_dir` | yes | string | Workspace-relative dir, usually `decisions/` |

### Example

```yaml
schema_version: 1

id: order-history
display_name: Order History
description: Order history feature spanning API, web, and downstream adapter repos
status: active
mode: interactive
objective: Let customers view historical orders with summary and detail flows
created_at: 2026-04-10

phase:
  current: prd
  last_completed: jam

repos:
  - repo_id: orders-api
    role: primary
    branch: main
    focus_areas:
      - src/Orders
      - tests/Orders.Api.Tests

  - repo_id: orders-web
    role: primary
    branch: main
    focus_areas:
      - src/features/order-history
      - tests/order-history

  - repo_id: customer-profile-adapter
    role: dependency
    branch: main
    focus_areas:
      - src/read-models

artifacts:
  refined_intent: refined-intent.md
  prd: prd/index.md
  tech_design: tech-design/index.md
  task_board_dir: task-boards/
  execution_plan_dir: execution-plans/
  decisions_dir: decisions/
```

### Validation Rules

- every `repo_id` must exist in `repos.yml`
- only participating repos belong here
- repo entries should not duplicate `remote` or `local_path`
- `focus_areas` are relative to the selected repo root
- artifact paths should point to entry docs, not annexes
- artifact paths are relative to the workspace root
- `artifacts.task_board_dir` and `artifacts.decisions_dir` should stay inside the workspace directory, not point at root legacy paths

## `.helix/active-workspace.yml`

Purpose: track the currently active workspace for the meta repo.

This file is runtime state. It should stay tiny and should not duplicate workspace content.

### Schema

| Field | Required | Type | Notes |
|------|----------|------|------|
| `schema_version` | yes | integer | Start with `1` |
| `active` | yes | string or null | Workspace id or `null` |
| `updated_at` | no | string | ISO timestamp |

### Example

```yaml
schema_version: 1
active: order-history
updated_at: 2026-04-10T09:20:00Z
```

## `.helix/repo-state/<repo-id>.yml`

Purpose: record generated readiness and attachment state for one repo.

This file is generated by setup, doctor, or readiness scan logic. It is not the registry.

### Schema

| Field | Required | Type | Notes |
|------|----------|------|------|
| `schema_version` | yes | integer | Start with `1` |
| `repo_id` | yes | string | Must match `repos.yml` |
| `local_path` | yes | string | Relative path from the meta-repo root |
| `last_scanned_at` | yes | string | ISO timestamp |
| `present` | yes | boolean | Whether the repo exists locally |
| `git` | yes | map | Current git signals when available |
| `git.branch` | no | string or null | Current branch |
| `git.dirty` | yes | boolean | Whether there are local changes |
| `git.remote` | no | string or null | Origin URL when available |
| `readiness` | yes | map | Helix readiness outcome |
| `readiness.state` | yes | string | `missing`, `needs-onboarding`, `partial`, or `ready` |
| `readiness.reason` | yes | string | Short human-readable explanation |
| `readiness.recommended_next_step` | yes | string | `attach`, `onboard`, `refresh`, or `none` |
| `readiness.signals` | yes | map | Specific discovery signals |
| `readiness.signals.root_agents` | yes | boolean | Root `AGENTS.md` present |
| `readiness.signals.nested_agents` | yes | boolean | Nested `AGENTS.md` present |
| `readiness.signals.instructions` | yes | boolean | `.github/instructions/` present |
| `readiness.signals.repo_skills` | yes | boolean | `.github/skills/` present |
| `readiness.signals.tests_present` | yes | boolean | Test directories found |

### Example

```yaml
schema_version: 1
repo_id: orders-api
local_path: ../orders-api
last_scanned_at: 2026-04-10T09:20:00Z
present: true

git:
  branch: main
  dirty: false
  remote: https://github.com/acme/orders-api

readiness:
  state: partial
  reason: Repo has some Helix guidance but still needs onboarding refresh
  recommended_next_step: onboard
  signals:
    root_agents: true
    nested_agents: false
    instructions: true
    repo_skills: false
    tests_present: true
```

## `.helix/install-state.yml`

Purpose: record what Helix installed into the meta repo and how those paths are managed.

This file is generated and updated by Helix install/sync logic. It is not the plugin manifest.

Do use it for:

- source and version of the installed Helix core
- last install and sync times
- the list of Helix-managed paths
- sync strategies for those paths

Do not use it for:

- repo registry
- workspace definitions
- generated repo readiness state

### Schema

| Field | Required | Type | Notes |
|------|----------|------|------|
| `schema_version` | yes | integer | Start with `1` |
| `helix_core` | yes | map | Source of the installed core |
| `helix_core.kind` | yes | string | `local-path` or `plugin` |
| `helix_core.source` | yes | string | Local path or plugin identifier |
| `helix_core.version` | no | string | Installed version label |
| `installed_at` | yes | string | ISO timestamp |
| `last_sync_at` | no | string | ISO timestamp |
| `runtime_surface` | yes | map | Runtime-facing directories in the meta repo |
| `runtime_surface.agents_dir` | yes | string | Usually `.github/agents` |
| `runtime_surface.hooks_dir` | yes | string | Usually `.github/hooks` |
| `runtime_surface.prompts_dir` | yes | string | Usually `.github/prompts` |
| `runtime_surface.skills_dir` | yes | string | Usually `.github/skills` |
| `runtime_surface.instructions_file` | yes | string | Usually `.github/copilot-instructions.md` |
| `managed_paths` | yes | list | Installed and tracked files |
| `managed_paths[].path` | yes | string | Path relative to the meta-repo root |
| `managed_paths[].source` | yes | string | Path relative to the `helix-core` root |
| `managed_paths[].category` | yes | string | `agent`, `prompt`, `skill`, `doc`, `instruction`, `template` |
| `managed_paths[].sync_mode` | yes | string | `replace`, `seed-once`, or `merge-marked-sections` |
| `managed_paths[].required` | no | boolean | Whether Helix expects it to exist after sync |

### Example

```yaml
schema_version: 1

helix_core:
  kind: local-path
  source: ../helix-core
  version: 0.1.0-local

installed_at: 2026-04-10T09:15:00Z
last_sync_at: 2026-04-10T09:15:00Z

runtime_surface:
  agents_dir: .github/agents
  hooks_dir: .github/hooks
  prompts_dir: .github/prompts
  skills_dir: .github/skills
  instructions_file: .github/copilot-instructions.md

managed_paths:
  - path: .github/agents/helix.agent.md
    source: .github/agents/helix.agent.md
    category: agent
    sync_mode: replace
    required: true

  - path: .github/copilot-instructions.md
    source: .github/copilot-instructions.md
    category: instruction
    sync_mode: replace
    required: true

  - path: README.md
    source: templates/meta-repo.README.md.template
    category: doc
    sync_mode: merge-marked-sections
    required: true

  - path: AGENTS.md
    source: templates/meta-repo.AGENTS.md.template
    category: doc
    sync_mode: merge-marked-sections
    required: true

  - path: helix/docs/helix-process.md
    source: docs/helix-process.md
    category: doc
    sync_mode: replace
    required: true
```

### Validation Rules

- `managed_paths[].path` must be unique
- `sync_mode` must be explicit
- instance-owned files such as `repos.yml` and `workspaces/*` must not appear here

## Deferred Schemas

Still to be defined later:

- typed runtime state beyond install tracking

## Templates

Starter templates for these manifests live in:

- [`../templates/repos.yml.template`](../templates/repos.yml.template)
- [`../templates/workspace.yml.template`](../templates/workspace.yml.template)
- [`../templates/install-state.yml.template`](../templates/install-state.yml.template)
- [`../templates/active-workspace.yml.template`](../templates/active-workspace.yml.template)
- [`../templates/repo-state.yml.template`](../templates/repo-state.yml.template)
