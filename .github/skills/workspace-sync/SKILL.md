---
name: workspace-sync
description: Validates a prepared repo registry and workspace manifest, runs the script-owned workspace setup flow, verifies outcomes, and then handles optional follow-on setup work
argument-hint: "Workspace name (e.g. 'order-feature') or path to workspace.yml"
user-invocable: true
disable-model-invocation: true
---

# Workspace Sync Skill

Uses the script-owned workspace setup path once Helix is installed and the user has updated `repos.yml` plus `workspaces/{name}/workspace.yml`.

## Workflow

### 1. Confirm Helix Is Installed

- Check for `.helix/install-state.yml`, `repos.yml`, and `scripts/setup-workspace.ps1`
- If bootstrap is missing, stop and tell the user to run `scripts/init-meta-repo.ps1` first
- Do not try to install Helix from this skill

### 2. Validate The Registry And Workspace

`repos.yml` is an instance-owned file created during installation from `templates/repos.yml.template`. The workspace manifest lives at `workspaces/{name}/workspace.yml`.

```
repos.yml
workspaces/{name}/workspace.yml
```

Before setup:

- ensure `repos.yml` contains real repo definitions rather than sample placeholder values
- ensure every `workspace.repos[*].repo_id` resolves to a registry entry
- ensure the workspace manifest is complete enough for `scripts/setup-workspace.ps1`
- if either manifest is missing or still needs edits, pause and ask the user to update it before continuing

Registry example:
```yaml
repos:
  - id: service-a
    remote: https://github.com/your-org/service-a
    local_path: ../service-a
    default_branch: main
  - id: service-b
    remote: https://github.com/your-org/service-b
    local_path: ../service-b
    default_branch: main
```

Workspace example:
```yaml
id: order-history
description: Order history feature spanning service-a and service-b
status: active
repos:
  - repo_id: service-a
    role: primary
  - repo_id: service-b
    role: dependency
```

### 3. Run The Authoritative Setup Script

Run `scripts/setup-workspace.ps1` with the requested workspace name or manifest path.

- Pass `-CloneMissing` only when the user wants missing workspace repos cloned locally
- Pass `-FetchExisting` only when the user wants already-present repos refreshed
- Pass `-IncludeClaudeSettings` only when Claude Desktop configuration is explicitly requested
- Do not mutate `repos.yml` from this skill
- Do not implement clone logic here; the script is the source of truth

### 4. Verify Definitive Outcomes

After `scripts/setup-workspace.ps1` succeeds, verify:

- `workspaces/{name}/{name}.code-workspace` exists
- `.helix/active-workspace.yml` points at the selected workspace
- `.helix/repo-state/{repo-id}.yml` exists for every repo in the workspace manifest
- the status table from the script reflects the expected presence and readiness values

Report status using the generated repo-state files as the source of truth.

### 5. Optional Follow-On Setup

Only after baseline workspace attach succeeds:

- if repo-state says `needs-onboarding` or `partial`, run the `onboard` skill for those repos and refresh repo-state afterward
- if the user wants structural retrieval, enable or verify `code-review-graph` after the workspace is attached
- keep onboarding and graph registration separate from baseline attach success so failures are easy to diagnose

## Output

- Updated `.helix/active-workspace.yml`
- Generated `workspaces/{name}/{name}.code-workspace`
- Refreshed `.helix/repo-state/*.yml` for the workspace repos
- A setup report that separates baseline attach results from optional onboarding and graph work

## Error Handling

```markdown
# Workspace Sync: {name}

| Repo | Path | Present | Readiness | Branch | Next Step |
|------|------|---------|-----------|--------|-----------|
| service-a | ../service-a | yes | ready | main | none |
| service-b | ../service-b | cloned | partial | main | onboard |

Generated: {name}.code-workspace, .helix/repo-state/*.yml
Updated: .helix/active-workspace.yml
Optional: .claude/settings.local.json when Claude Desktop integration is explicitly requested
```

- Helix not installed → stop and point to `scripts/init-meta-repo.ps1`
- `repos.yml` or `workspace.yml` missing or still using placeholder values → stop and ask the user to repair the manifests
- `setup-workspace.ps1` fails → surface the script output and do not continue to onboarding or graph setup
- Onboard fails → report error and leave repo-state at `partial` or `needs-onboarding`
- Graph setup fails → report it separately from baseline workspace attach

## Prerequisites

- Helix bootstrap already completed via `scripts/init-meta-repo.ps1` or the equivalent installer flow
- `repos.yml` has been updated with the real repo registry
- `workspaces/{name}/workspace.yml` has been created or updated with the participating repos
- `git` available
- Prefer [`scripts/setup-workspace.ps1`](../../../scripts/setup-workspace.ps1) for the target meta-repo model; the old Bash helper is legacy
