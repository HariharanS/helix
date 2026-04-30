---
name: hc-review-pr
managed-by: helix-core
description: Full PR review with blast-radius analysis — comprehensive structural review across all commits in a PR or branch, feeding into the reviewer's semantic lenses.
argument-hint: "[branch-name or PR base ref] — defaults to git merge-base against origin/main"
user-invocable: true
disable-model-invocation: true
---

# Review PR Skill

Performs a comprehensive structural review of a pull request or branch diff, combining `detect_changes_tool` risk scoring with blast-radius analysis across all commits. The calling agent (reviewer) then applies its semantic lenses (Security, Correctness, Domain Logic, etc.) using this structural output as input.

## Workflow

### 1. Check Mode

Read `.helix/context-providers.yml`.

- `mode: mcp` → proceed with Step 2; CRG tool failure is a setup gap
- `mode: off` → skip to Step 7 (emergency manual fallback)

### 2. Resolve Repo Root and Base Ref

#### Repo Root
Same as `/hc-review-delta`: if the caller passed a `repo-path`, use it. Otherwise resolve from `workspace.yml` repo ids plus `.helix/repo-state/{repo-id}.yml.local_path` by finding the repo with changes against the PR base.

#### Base Ref
Derive from actual git state — do NOT hardcode `main`:

```powershell
# Prefer the PR's recorded base branch if available
# Otherwise compute the merge-base
$base = git -C "{resolved-repo-path}" merge-base HEAD origin/HEAD 2>$null
if (-not $base) {
    $base = git -C "{resolved-repo-path}" rev-parse origin/HEAD
}
```

Use `$base` (commit SHA) as the diff base for all CRG tool calls. This ensures correctness regardless of the default branch name (`main`, `master`, `develop`, etc.).

### 3. Update Graph Against PR Base

```
build_or_update_graph_tool(
  base="{base-sha}",
  repo_root="{resolved-repo-path}"
)
```

### 4. Risk-Scored Change Detection (primary)

```
detect_changes_tool(
  base="{base-sha}",
  include_source=true,
  max_depth=2,
  detail_level="standard",
  repo_root="{resolved-repo-path}"
)
```

This is the primary review primitive across the full PR diff. Returns:
- All changed functions with source snippets
- Risk scores (LOW / MEDIUM / HIGH)
- Affected flows and communities
- Test coverage gaps
- Prioritised review items

### 5. Blast-Radius Overview

```
get_impact_radius_tool(
  base="{base-sha}",
  max_depth=2,
  detail_level="standard",
  repo_root="{resolved-repo-path}"
)
```

Provides a broad view of which files, functions, and modules are impacted across the whole PR. Use this to identify high-risk hotspots before deep-diving.

### 6. Selective Deep-Dives

For nodes flagged HIGH risk (limit: top 5 by risk score to stay within budget):

```
query_graph_tool(pattern="callers_of",   target="{high-risk-function}", repo_root="{resolved-repo-path}")
query_graph_tool(pattern="tests_for",    target="{high-risk-function}", repo_root="{resolved-repo-path}")
query_graph_tool(pattern="inheritors_of",target="{high-risk-class}",    repo_root="{resolved-repo-path}")
```

Only call `inheritors_of` when the HIGH-risk node is a class or interface. If affected flows are present in `detect_changes_tool` output, call once:

```
get_affected_flows_tool(base="{base-sha}", repo_root="{resolved-repo-path}")
```

### 7. Manual Fallback (mode: off only)

```powershell
git -C "{resolved-repo-path}" diff "{base-sha}"...HEAD
```

Read the changed files directly. Manually identify callers and test coverage from code.

### 8. Structured Output

Produce the following block for the calling hc-reviewer agent:

```markdown
## CRG PR Analysis

### Summary
- **Branch/PR**: {branch or PR ref}
- **Base ref**: {base-sha short}
- **Changed files**: N files, M functions
- **Overall risk**: Low / Medium / High
- **Blast radius**: X files, Y functions impacted
- **Test coverage**: N changed functions with tests / M total changed functions

### Risk-Prioritised Changes
| Node | File | Risk | Blast Radius | Tests |
|------|------|------|--------------|-------|
| FuncName | path/file.cs | HIGH | 5 impacted | 0 tests |

### Missing Tests
- `FunctionName` in `path/file.cs` — no test coverage found

### Affected Execution Flows
- FlowName — passes through high-risk node X

### Structural Recommendations
- Prioritised findings from detect_changes_tool
```

The reviewer then applies its semantic lenses (Security, Correctness, Domain Logic, Coding Style, Test Coverage) on top of this structural output.

## Budget

Stay within `max_tool_calls_per_task` from `context-providers.yml` (default 10). Typical call count:
- 1 `build_or_update_graph_tool`
- 1 `detect_changes_tool`
- 1 `get_impact_radius_tool`
- Up to 2 `query_graph_tool` per high-risk node (limit 5 nodes = 10 calls max — drop `get_impact_radius_tool` if near limit)
- 1 optional `get_affected_flows_tool`

For large PRs (>20 changed files), report the top-10 highest-risk nodes and note the total count.
