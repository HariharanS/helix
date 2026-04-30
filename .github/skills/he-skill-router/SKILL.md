---
name: he-skill-router
managed-by: helix-core
description: Resolve and load the right Helix skill guidance before repo-specific work
argument-hint: "Repo id, paths, and short task description"
user-invocable: true
disable-model-invocation: true
---

# Helix Skill Router

Use this before repo-specific work and in every Helix subagent handoff that can touch product repos.

## Contract

1. Resolve the active workspace from `.helix/active-workspace.yml`.
2. Read `.helix/skills/index.yml`.
3. Select matching skill guidance by repo, path, task, and phase.
4. Prefer projected `hr-*` skills under `.github/skills/`.
5. Fall back to the repo-local `SKILL.md` referenced by the registry.
6. Emit a `skill_use` record before acting.

## Recommended Resolver

When available, run:

```powershell
./helix/scripts/resolve-skill.ps1 -RepoId <repo-id> -Path <path> -Task "<task>"
```

Then read the returned `skill_use.source_path` before changing files.

## Required Skill Use Record

```yaml
skill_use:
  task_repo: <repo-id>
  selected_skill: <skill-id-or-null>
  source_path: <path-or-null>
  status: <core|projected|candidate|no_match|no_registry|needs_disambiguation>
  fallback: <core|projected|repo-local|none>
  selection_reason: <short reason>
```

If `status` is `needs_disambiguation`, stop and ask for a narrower repo/path/task unless the execution plan already resolves the ambiguity.
