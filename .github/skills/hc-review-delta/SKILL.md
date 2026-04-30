---
name: hc-review-delta
managed-by: helix-core
description: Token-efficient incremental code review — blast-radius analysis for changes since last commit, feeding into the reviewer's semantic lenses.
argument-hint: "[repo-path] — optional explicit path to the changed repo"
user-invocable: true
disable-model-invocation: true
---

# Review Delta Skill

Performs a focused, token-efficient structural review of changes since the last commit (or a specified base ref). Uses `detect_changes_tool` as the primary signal — it maps diffs to affected functions, flows, communities, and test coverage gaps with risk scoring. The calling agent (reviewer) then applies its semantic lenses (Security, Correctness, Domain Logic, etc.) using this structural output as input.

## Prerequisite

If implementation work has just completed, run `/hc-build-graph` first. A stale graph produces misleading blast-radius output.

## Workflow

### 1. Check Mode

Read `.helix/context-providers.yml`.

- `mode: mcp` → proceed with Step 2; CRG tool failure is a setup gap
- `mode: off` → skip to Step 6 (emergency manual fallback)

### 2. Resolve Repo Root

Determine which product repo contains the changes:

1. If the caller passed `repo-path` as the argument, use it directly.
2. Otherwise read `workspaces/{name}/workspace.yml`, then resolve each repo's checkout root from `.helix/repo-state/{repo-id}.yml.local_path` and check each repo for recent changes:
   ```powershell
   git -C "{repo-state.local_path}" diff --name-only HEAD~1
   ```
   Use the repo that returns changed files as the target. If multiple repos have changes, run Steps 3–5 once per repo.

### 3. Incremental Graph Update

Call `build_or_update_graph_tool()` with the resolved repo root:

```
build_or_update_graph_tool(repo_root="{resolved-repo-path}")
```

### 4. Risk-Scored Change Detection (primary)

Call `detect_changes_tool` with source snippets and standard detail:

```
detect_changes_tool(
  include_source=true,
  max_depth=2,
  detail_level="standard",
  repo_root="{resolved-repo-path}"
)
```

This is the primary review primitive. It returns:
- Changed functions with source snippets
- Risk score per change (LOW / MEDIUM / HIGH)
- Affected flows and communities
- Test coverage gaps
- Prioritised review items

### 5. Selective Deep-Dives

Only for nodes flagged HIGH risk by `detect_changes_tool` (limit: top 3 to stay within `max_tool_calls_per_task` budget):

```
query_graph_tool(pattern="callers_of", target="{high-risk-function}", repo_root="{resolved-repo-path}")
query_graph_tool(pattern="tests_for",  target="{high-risk-function}", repo_root="{resolved-repo-path}")
```

If `detect_changes_tool` reported affected flows, call once:

```
get_affected_flows_tool(repo_root="{resolved-repo-path}")
```

### 6. Manual Fallback (mode: off only)

```powershell
git -C "{resolved-repo-path}" diff HEAD~1
```

Read the changed files directly. Manually trace callers and test coverage from code.

### 7. Structured Output

Produce the following block for the calling hc-reviewer agent:

```markdown
## CRG Delta Analysis

### Risk Assessment
- **Overall risk**: Low / Medium / High
- **Changed nodes**: N functions, M classes
- **Blast radius**: X files, Y functions impacted
- **Test coverage gaps**: list missing tests

### High-Risk Changes
| Node | File | Risk | Callers | Tests |
|------|------|------|---------|-------|
| FuncName | path/file.cs | HIGH | 3 | 0 |

### Affected Flows
- FlowName — passes through changed node X (criticality: high)

### Structural Findings
- Prioritised review items from detect_changes_tool
```

The reviewer applies its semantic lenses (Security, Correctness, Domain Logic, Coding Style, Test Coverage) on top of this structural output.

## Budget

Stay within `max_tool_calls_per_task` from `context-providers.yml` (default 10). Typical call count:
- 1 `build_or_update_graph_tool`
- 1 `detect_changes_tool`
- Up to 2 `query_graph_tool` per high-risk node (limit 3 nodes = 6 calls)
- 1 optional `get_affected_flows_tool`
= 9 calls max
