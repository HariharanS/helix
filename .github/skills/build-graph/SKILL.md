---
name: build-graph
managed-by: helix-core
description: Build or incrementally update the code-review-graph for all active workspace repos, register them for cross-repo search, and verify graph readiness.
argument-hint: "[full] — pass 'full' to force a complete rebuild of all repos"
user-invocable: true
disable-model-invocation: true
---

# Build Graph Skill

Build or incrementally update the code-review-graph for every repo in the active workspace. Also registers repos for cross-repo search (`cross_repo_search_tool`) and generates wiki pages. This is normally handled by workspace setup; use this skill for manual repair or refresh.

## Workflow

### 1. Check Configuration

- Read `.helix/context-providers.yml` — if `mode: off`, report CRG is in emergency fallback and stop. The user must set `mode: mcp` before a build is meaningful.
- Read `.helix/active-workspace.yml` for the workspace name.
- Read `workspaces/{name}/workspace.yml` for the `repos` list.
- Read `.helix/repo-state/{repo-id}.yml` for each workspace repo and use `local_path` as the authoritative checkout root.
- Use the CRG runner configured by setup (`uvx code-review-graph`, `code-review-graph`, or `python -m code_review_graph`). Command snippets below use the Python form as an example.

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

### 6. Keep `context-providers.yml` Mode

Do not automatically change `context-providers.yml` based on build results. Normal Helix setup expects `mode: mcp`; a failed build is a setup gap to repair. Only set `mode: off` when the user explicitly requests emergency default-agent/search behavior.

### 7. Report

Per repo:
- Status: built / updated / failed / skipped
- Node count and edge count
- Languages detected
- Any errors

Overall:
- CRG mode remains `mcp` unless the user explicitly changed it
- Which repos are ready for graph-assisted queries
- Cross-repo registration status

## When to Use

- After workspace setup when a manual repair or full refresh is needed
- After switching branches or after a large merge
- When `/curate-context` reports a missing or stale graph in `mode: mcp`
- When `/review-delta` or `/review-pr` detect a stale or missing graph

## Notes

- The graph database lives at `.code-review-graph/graph.db` inside each product repo
- Git-ignored files are skipped automatically; use `.code-review-graphignore` for tracked exclusions
- Do NOT run this mid-flight during a fleet implementation loop — only at phase boundaries
- Flow analysis (`list_flows_tool`, `get_affected_flows_tool`) is expected to be populated by the normal full build path. If a graph was created through an older `--skip-flows` path, run `full` to refresh it before review phases.
