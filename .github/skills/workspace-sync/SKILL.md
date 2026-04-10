---
name: workspace-sync
description: Attaches the repos selected by a workspace, refreshes repo-state, generates the VS Code .code-workspace file, and activates the workspace
argument-hint: "Workspace name (e.g. 'order-feature') or path to workspace.yml"
user-invocable: true
disable-model-invocation: true
---

# Workspace Sync Skill

Sets up a workspace by reading the repo registry plus one workspace manifest, attaching only the repos that feature-space needs, refreshing repo-state, and generating IDE configuration.

## Workflow

### 1. Read The Registry And Workspace

```
repos.yml
workspaces/{name}/workspace.yml
```

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

### 2. For Each Repo

```
a. Look up repo_id in repos.yml

b. Path exists?
   YES → git fetch + git status (report if behind remote)
   NO  → Clone the repo:
         - Azure DevOps URLs → az repos clone
         - GitHub URLs → gh repo clone
         - Other → git clone

c. Refresh `.helix/repo-state/{repo-id}.yml`
   - capture presence
   - capture git branch / remote / dirty status when available
   - capture readiness signals:
     - root `AGENTS.md`
     - nested `AGENTS.md`
     - `.github/instructions/`
     - `.github/skills/`
     - tests present

d. If repo-state says `needs-onboarding` or `partial`
   YES → Run onboard skill against that repo
         → Re-scan and update repo-state
```

### 3. Generate VS Code Workspace File

Create `workspaces/{name}/{name}.code-workspace`:

```json
{
  "folders": [
    { "name": "meta-repo", "path": "../.." },
    { "name": "service-a", "path": "../../../service-a" },
    { "name": "service-b", "path": "../../../service-b" }
  ],
  "settings": {
    "chat.agentFilesLocations": [{ "source": ".github/agents" }],
    "chat.skillsLocations": [{ "source": ".github/skills" }],
    "chat.hookFilesLocations": [{ "source": "hooks" }]
  }
}
```

### 4. Update .claude/settings.local.json

Add repo paths to `additionalDirectories` for Copilot CLI access:

```json
{
  "permissions": {
    "additionalDirectories": [
      "../service-a",
      "../service-b"
    ]
  }
}
```

### 5. Set Active Workspace

Update `.helix/active-workspace.yml`:
```yaml
active: order-feature
```

### 6. Report Status

```markdown
# Workspace Sync: {name}

| Repo | Path | Present | Readiness | Branch | Next Step |
|------|------|---------|-----------|--------|-----------|
| service-a | ../service-a | yes | ready | main | none |
| service-b | ../service-b | cloned | partial | main | onboard |

Generated: {name}.code-workspace, .helix/repo-state/*.yml
Updated: .claude/settings.local.json, .helix/active-workspace.yml
```

## Error Handling

- Clone fails → report error, continue with other repos
- Onboard fails → report error, leave repo-state at `partial` or `needs-onboarding`, continue
- Repo behind remote → warn but don't auto-pull (developer decision)
- Workspace repo_id missing from repos.yml → stop and ask for registry repair

## Prerequisites

- `az` CLI authenticated (for Azure DevOps repos)
- `gh` CLI authenticated (for GitHub repos)
- `git` available
- Prefer [`scripts/setup-workspace.ps1`](C:\Users\Harih\source\personal\github-copilot-multi-agent-setup\helix\scripts\setup-workspace.ps1) for the target meta-repo model; the old Bash helper is legacy
