---
name: workspace-sync
managed-by: helix-core
description: Validates a prepared repo registry and workspace manifest, runs the script-owned workspace setup flow, verifies outcomes, and then handles optional follow-on setup work
argument-hint: "Workspace name (e.g. 'order-feature') or path to workspace.yml"
user-invocable: true
disable-model-invocation: true
---

# Workspace Sync Skill

Uses the script-owned workspace setup path once Helix is installed and the user has updated `helix-repos.yml` plus `workspaces/{name}/workspace.yml`.

## Workflow

### 1. Confirm Helix Is Installed

- Check for `.helix/install-state.yml`, `helix-repos.yml` (or legacy `repos.yml`), and `helix/scripts/workspace-setup.ps1`
- If bootstrap is missing, stop and tell the user to run `init.ps1` from the Helix source repo first
- Do not try to install Helix from this skill

### 2. Validate The Registry And Workspace

`helix-repos.yml` is the canonical instance-owned registry file created during installation from `helix/templates/helix-repos.yml.template`. `repos.yml` remains the legacy compatibility alias. The workspace manifest lives at `workspaces/{name}/workspace.yml`.

```
helix-repos.yml
workspaces/{name}/workspace.yml
```

Before setup:

- ensure `helix-repos.yml` (or legacy `repos.yml`) contains real repo definitions rather than sample placeholder values
- ensure every `workspace.repos[*].repo_id` resolves to a registry entry
- ensure the workspace manifest is complete enough for `helix/scripts/workspace-setup.ps1`
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

Run `helix/scripts/workspace-setup.ps1` with the requested workspace name or manifest path.

- Pass `-CloneMissing` only when the user wants missing workspace repos cloned locally
- Pass `-FetchExisting` only when the user wants already-present repos refreshed
- Pass `-IncludeClaudeSettings` only when Claude Desktop configuration is explicitly requested
- Do not mutate `helix-repos.yml` or `repos.yml` from this skill
- Do not implement clone logic here; the script is the source of truth

### 4. Verify Definitive Outcomes

After `helix/scripts/workspace-setup.ps1` succeeds, verify:

- `{name}.code-workspace` exists at the meta-repo root
- `.helix/active-workspace.yml` points at the selected workspace
- `.helix/repo-state/{repo-id}.yml` exists for every repo in the workspace manifest
- `.github/instructions/{name}.workspace.instructions.md` exists, along with any generated repo instruction summaries
- the status table from the script reflects the expected presence and readiness values

Report status using the generated repo-state files as the source of truth.

### 5. Optional Follow-On Setup

Only after baseline workspace attach succeeds:

#### 5a. Onboard Repos

Run the `onboard` skill for each repo marked `needs-onboarding` or `partial` in repo-state. Run repos in parallel where possible. Each onboard run produces a **Cross-Cutting Patterns table** — collect these outputs.

#### 5b. Refresh Repo-State

After all onboarding completes, re-run `helix/scripts/workspace-setup.ps1 -Workspace {name}` with no additional flags. This re-scans all repos and accurately updates every signal (`root_agents`, `instructions`, `repo_skills`, `tests_present`, `nested_agents`). Do NOT manually patch `.helix/repo-state/*.yml` files.

#### 5c. Review Cross-Cutting Promotion Candidates

Aggregate the promotion tables from all onboard outputs. Deduplicate by pattern name. Present the consolidated table to the user for approval before creating any meta-repo skills.

Gate for promotion — all must be true:
- Pattern appears in 2 or more repos
- Consistent parameterization across repos
- No existing meta-repo skill already covers it (check `{meta-repo}/.github/skills/`)

After human approval, for each approved pattern:
- Create `{meta-repo}/.github/skills/{suggested-skill-name}/SKILL.md` with correct frontmatter (`managed-by: user`; use the `maker` skill for schema)
- Remove any duplicate repo-level SKILL.md files generated for the same pattern

#### 5d. Create Workspace Platform AGENTS.md

Create or update `workspaces/{name}/AGENTS.md` as a platform-level architecture document. Include:
- All repos in the workspace, their roles, and primary responsibilities
- End-to-end data flow diagram (mermaid) showing how repos connect
- Shared patterns and conventions common across repos
- Cross-repo glossary terms
- Read-order recommendation for agents working across this workspace

Add this retrieval note at the top:

```
> Agents working in this workspace should read this file before reading individual repo AGENTS.md files.
> It provides platform-level context that individual repo docs do not repeat.
```

#### 5e. Enable Code-Review-Graph (optional)

Enable or verify `code-review-graph` only when the user explicitly wants structural retrieval during setup. Keep this step separate from baseline attach and onboarding success.

## Output

- Updated `.helix/active-workspace.yml`
- Generated `{name}.code-workspace` at the meta-repo root
- Generated `.github/instructions/*.instructions.md` summaries for the workspace and participating repos
- Refreshed `.helix/repo-state/*.yml` for the workspace repos (via script, not manual edits)
- A setup report that separates baseline attach results from optional onboarding and graph work

## Error Handling

```markdown
# Workspace Sync: {name}

| Repo | Path | Present | Readiness | Branch | Next Step |
|------|------|---------|-----------|--------|-----------|
| service-a | workspaces/order-history/repos/service-a | yes | ready | main | none |
| service-b | workspaces/order-history/repos/service-b | cloned | partial | main | onboard |

Generated: {name}.code-workspace, .github/instructions/*.instructions.md, .helix/repo-state/*.yml
Updated: .helix/active-workspace.yml
Optional: .claude/settings.local.json when Claude Desktop integration is explicitly requested
```

- Helix not installed → stop and point to `init.ps1` from the Helix source repo
- `helix-repos.yml` (or legacy `repos.yml`) or `workspace.yml` missing or still using placeholder values → stop and ask the user to repair the manifests
- `workspace-setup.ps1` fails → surface the script output and do not continue to onboarding or graph setup
- Onboard fails → report error and leave repo-state at `partial` or `needs-onboarding`
- Graph setup fails → report it separately from baseline workspace attach

## Prerequisites

- Helix bootstrap already completed via `init.ps1` from the Helix source repo or the equivalent installer flow
- `helix-repos.yml` has been updated with the real repo registry (`repos.yml` is accepted only as a legacy alias)
- `workspaces/{name}/workspace.yml` has been created or updated with the participating repos
- `git` available
- Prefer `helix/scripts/workspace-setup.ps1` for the target meta-repo model; the old Bash helper is legacy
