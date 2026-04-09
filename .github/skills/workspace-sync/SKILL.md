---
name: workspace-sync
description: Clones workspace repos, runs onboard on each, generates VS Code .code-workspace file, and updates .claude/settings.json
argument-hint: "Workspace name (e.g. 'order-feature') or path to workspace.yaml"
user-invocable: true
disable-model-invocation: true
---

# Workspace Sync Skill

Sets up a workspace by cloning repos, onboarding them, and generating IDE configuration.

## Workflow

### 1. Read Workspace Definition

```
workspaces/{name}/workspace.yaml
```

Expected format:
```yaml
name: order-feature
description: Order history feature spanning service-a and service-b
status: created
created: 2026-04-09
repos:
  - path: ../service-a
    url: https://dev.azure.com/org/project/_git/service-a
    branch: main
    role: primary
    onboarded: true
  - path: ../service-b
    url: https://dev.azure.com/org/project/_git/service-b
    branch: main
    role: dependency
    onboarded: false
```

### 2. For Each Repo

```
a. Path exists?
   YES → git fetch + git status (report if behind remote)
   NO  → Clone the repo:
         - Azure DevOps URLs → az repos clone
         - GitHub URLs → gh repo clone
         - Other → git clone

b. onboarded: false?
   YES → Run onboard skill against that repo
         → Set onboarded: true in workspace.yaml

c. onboarded: true AND --refresh flag?
   YES → Run onboard --refresh against that repo
```

### 3. Generate VS Code Workspace File

Create `workspaces/{name}/{name}.code-workspace`:

```json
{
  "folders": [
    { "name": "helix", "path": "../.." },
    { "name": "service-a", "path": "../../../service-a" },
    { "name": "service-b", "path": "../../../service-b" }
  ],
  "settings": {}
}
```

### 4. Update .claude/settings.json

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

Update `.helix/active-workspace.yaml`:
```yaml
active: order-feature
```

### 6. Report Status

```markdown
# Workspace Sync: {name}

| Repo | Path | Exists | Onboarded | Branch | Status |
|------|------|--------|-----------|--------|--------|
| service-a | ../service-a | yes | yes | main | up to date |
| service-b | ../service-b | cloned | yes (new) | main | fresh clone |

Generated: {name}.code-workspace
Updated: .claude/settings.json, .helix/active-workspace.yaml
```

## Error Handling

- Clone fails → report error, continue with other repos
- Onboard fails → report error, set onboarded: false, continue
- Repo behind remote → warn but don't auto-pull (developer decision)

## Prerequisites

- `az` CLI authenticated (for Azure DevOps repos)
- `gh` CLI authenticated (for GitHub repos)
- `git` available
