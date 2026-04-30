---
name: hc-curate-context
managed-by: helix-core
description: Graph-first context curation — uses code-review-graph to discover relevant code, classifies files into primary/secondary/tertiary tiers, writes a context bundle
argument-hint: "Task description and optional seed files (e.g. 'Add order cancellation endpoint' or 'TASK-003')"
user-invocable: true
disable-model-invocation: true
---

# Curate Context Skill

Produces a tiered context bundle for a task using code-review-graph as the primary retrieval engine. Use CRG first for code navigation, symbol lookup, flows, blast radius, and cross-repo search. Manual fallback is allowed only when the operator explicitly sets `mode: off` — a missing or stale graph in `mode: mcp` is a hard setup error.

## Workflow

### 1. Read Workspace Config

- Read `.helix/active-workspace.yml` for the active workspace name
- Read `workspaces/{name}/workspace.yml` for the repo list
- Read `.helix/context-providers.yml` for CRG mode and budgets
- If `code_review_graph.mode` is `off`, skip to Step 6 (manual fallback — operator opted out)
- If `code_review_graph.mode` is `mcp`, continue to Step 2 (probe before MCP calls)

### 2. Readiness Probe (mode: mcp only)

Before invoking any MCP tools, verify the graph is built:

```powershell
# Example runner; use the CRG runner configured by setup if it differs.
python -m code_review_graph status --repo {primary-repo-path}
```

- Exit 0 and `nodes > 0` → proceed with MCP tool calls below
- Exit non-zero or `nodes = 0` → **HARD ERROR** (do not silently fall back). Stop and surface the failure to the user with the exact remediation:

  > CRG is configured as `mode: mcp` in `.helix/context-providers.yml` but the graph for `{primary-repo-path}` reports {0 nodes | exit code N}. Run `/hc-build-graph` (or `python -m code_review_graph build --repo {primary-repo-path}`) to build it, then re-run this skill. To explicitly opt out of graph-based retrieval, set `mode: off` in `.helix/context-providers.yml` — manual fallback is reserved for that case.

  Do NOT proceed to Step 6. Manual fallback in `mode: mcp` masks the misconfiguration and produces low-confidence bundles that downstream agents trust as if they were graph-derived.

### 2a. Graph-First Retrieval (MCP)

a. Call `get_minimal_context_tool(task="<task description>")` to get ~100 tokens with risk assessment, communities, flows, and suggested next tools

b. Follow CRG's suggested tools to expand context:
   - `query_graph_tool` for callers/callees/inheritance/imports from relevant symbols
   - `cross_repo_search_tool` for cross-repo dependencies (when workspace has 2+ repos)
   - `semantic_search_nodes_tool` for fuzzy entity matching when symbol names are uncertain
   - `get_affected_flows_tool` for execution flow context (HTTP handlers, event handlers, Lambda entry points)
   - `list_communities_tool` / `get_community_tool` for architectural groupings
   - `get_architecture_overview_tool` for high-level structure (useful in tech-design tasks)
   - `get_review_context_tool` for token-optimised change review context (useful in reviewer tasks)

c. Use the configured `detail_level` from `.helix/context-providers.yml` on all calls. The config file is the control point — do not hardcode a level here.

d. Use `get_docs_section_tool` if unsure how a CRG tool works (self-serve docs).

e. Stay within the configured `max_tool_calls_per_task` and `max_context_tokens_per_task` budgets from context-providers.yml.

### 3. Classify Into Tiers

From the graph results, classify every discovered file/symbol:

- **Primary:** Files directly involved in the task — entry points, files to be modified, core domain logic. Read these files fully and include relevant content in the bundle.
- **Secondary:** Files one hop away — callers, callees, implementors, interfaces. Include signatures and structural summary only (from CRG's node data). Do NOT read full file content.
- **Tertiary:** Files two+ hops away — tests for primary files, shared utilities, transitive dependencies. Include path + symbol + reason only.

When classifying, prefer depth over breadth:
- A task touching one endpoint should have 2-4 primary files, 5-10 secondary, and 10-20 tertiary
- If you're classifying more than 30 files as primary, you're too broad — re-scope

### 4. Gap-Fill

Scan manually only for what CRG's code graph cannot provide or cannot answer confidently:

- Domain docs, ADRs, README context relevant to the task
- SAM/CloudFormation templates for infrastructure relationships (Lambda -> DynamoDB -> EventBridge)
- root and nested `AGENTS.md` conventions in each relevant repo
- Cross-repo shared contracts or interfaces that `cross_repo_search_tool` didn't surface

Do NOT re-scan code that CRG already indexed. If a file appeared in graph results, trust the graph.

### 5. Write Context Bundle

Write the bundle to `workspaces/{workspace}/context-bundle-{task-id}.md` using the tiered context bundle template from `helix/templates/context-bundle.md.template`.

Populate:
- Frontmatter: task_id, question, primary_repo, confidence, last_verified (today's date)
- Context Tiers: Primary, Secondary, Tertiary sections with classified files
- Domain, Anchors, Patterns, Contracts, Tests, Infra: from gap-fill and graph evidence
- Read Order: Primary files first, then secondary if needed
- Source attribution: mark each entry as `crg:tool_name` or `manual`

### 6. Manual Fallback (mode: off ONLY)

This step runs **only** when `code_review_graph.mode` is explicitly `off` in `.helix/context-providers.yml`. A missing graph in `mode: mcp` is a hard error in Step 2 — do not route here from a probe failure.

1. Fall back to manual multi-pass repo scanning:
   - Directory scan for structure
   - Targeted reads based on task description keywords
   - Test pattern discovery
2. Still write a tiered context bundle, but mark `source: manual` on all entries
3. Set `confidence: low` in the frontmatter
4. Add to Open Questions: "CRG mode is 'off' — context derived from manual scanning only. Set `mode: mcp` and run `/hc-build-graph` for graph-assisted curation."

## Guidelines

- Token economy matters — keep bundles scannable, not exhaustive
- Every non-obvious claim must be backed by evidence or labeled as inference
- Prefer `path + symbol + anchor_text` over path alone for resilient references
- If the task spans multiple repos, produce one unified bundle (not per-repo)
- If the bundle exceeds ~200 lines, move detail into an annex file: `context-bundle-{task-id}.annex.md`
