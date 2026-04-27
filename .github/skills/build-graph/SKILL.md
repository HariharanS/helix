---
name: build-graph
managed-by: helix-core
description: Build or incrementally update the code-review-graph for all active workspace repos, register them for cross-repo search, and sync context-providers.yml mode.
argument-hint: "[full] — pass 'full' to force a complete rebuild of all repos"
user-invocable: true
disable-model-invocation: true
---

# Build Graph Skill

Build or incrementally update the code-review-graph for every repo in the active workspace. Also registers repos for cross-repo search (`cross_repo_search_tool`) and updates `context-providers.yml` mode based on results.

## Workflow

### 1. Check Configuration

- Read `.helix/context-providers.yml` — if `mode: off`, report CRG is disabled and stop. The user must set `mode: mcp` before a build is meaningful.
- Read `.helix/active-workspace.yml` for the workspace name.
- Read `workspaces/{name}/workspace.yml` for the `repos` list.
- Read `.helix/repo-state/{repo-id}.yml` for each workspace repo and use `local_path` as the authoritative checkout root.

### 2. Check Graph Status Per Repo

For each repo in `workspace.repos`, using `.helix/repo-state/{repo-id}.yml.local_path`:

```powershell
python -m code_review_graph status --repo "{repo-state.local_path}"
```

Classify result:
- Exit 0 + `nodes > 0` and no `full` argument → **incremental update** (Step 3b)
- Exit 0 + `nodes = 0`, exit non-zero, or `full` argument passed → **full build** (Step 3a)

### 3. Build or Update

Run for each repo. If the relative path produces 0 nodes or errors, retry with the full absolute path.

#### 3a. Full Build

```powershell
python -m code_review_graph build --repo "{repo-state.local_path}"
```

#### 3b. Incremental Update

```powershell
python -m code_review_graph update --repo "{repo-state.local_path}"
```

### 4. Register Repos for Cross-Repo Search

`cross_repo_search_tool` requires repos to be registered. After a successful build (nodes > 0), register each repo:

```powershell
python -m code_review_graph register "{repo-state.local_path}"
```

If the repo is already registered, this is a no-op.

### 5. Generate Wiki Pages

After a successful build or update, generate wiki pages for agent navigation:

```powershell
python -m code_review_graph wiki --repo "{repo-state.local_path}"
```

### 6. Update `context-providers.yml` Mode

Based on aggregate results:

- At least one repo built successfully (nodes > 0) → set `mode: mcp`
- All repos have 0 nodes or build failed → set `mode: off`
- If the user deferred this step → leave `mode` unchanged

### 7. Report

Per repo:
- Status: built / updated / failed / skipped
- Node count and edge count
- Languages detected
- Any errors

Overall:
- CRG mode now in `context-providers.yml`
- Which repos are ready for graph-assisted queries
- Cross-repo registration status

## When to Use

- After workspace setup (step 7 of setup.agent.md calls this pattern directly)
- After switching branches or after a large merge
- When `/curate-context` falls back to manual mode unexpectedly
- When `/review-delta` or `/review-pr` detect a stale or missing graph

## Notes

- The graph database lives at `.code-review-graph/graph.db` inside each product repo
- Git-ignored files are skipped automatically; use `.code-review-graphignore` for tracked exclusions
- Do NOT run this mid-flight during a fleet implementation loop — only at phase boundaries
- Flow analysis (`list_flows_tool`, `get_affected_flows_tool`) is populated by default. If the build was originally run with `--skip-flows` (as in setup.agent.md step 7), run `update` to populate flows before review phases
