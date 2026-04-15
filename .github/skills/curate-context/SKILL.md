---
name: curate-context
managed-by: helix-core
description: Graph-first context curation — uses code-review-graph to discover relevant code, classifies files into primary/secondary/tertiary tiers, writes a context bundle
argument-hint: "Task description and optional seed files (e.g. 'Add order cancellation endpoint' or 'TASK-003')"
user-invocable: true
disable-model-invocation: true
---

# Curate Context Skill

Produces a tiered context bundle for a task using code-review-graph as the primary retrieval engine. Falls back to manual scanning if CRG is unavailable.

## Workflow

### 1. Read Workspace Config

- Read `.helix/active-workspace.yml` for the active workspace name
- Read `workspaces/{name}/workspace.yml` for the repo list
- Read `.helix/context-providers.yml` for CRG mode and budgets
- If `code_review_graph.mode` is `off` or CRG is not installed, skip to step 5 (fallback)

### 2. Graph-First Retrieval

a. Call `get_minimal_context_tool(task="<task description>")` to get ~100 tokens with risk assessment, communities, flows, and suggested next tools

b. Follow CRG's suggested tools to expand context:
   - `query_graph_tool` for callers/callees/inheritance/imports from relevant symbols
   - `cross_repo_search_tool` for cross-repo dependencies (when workspace has 2+ repos)
   - `semantic_search_nodes_tool` for fuzzy entity matching when symbol names are uncertain
   - `get_affected_flows_tool` for execution flow context (HTTP handlers, event handlers, Lambda entry points)
   - `list_communities_tool` / `get_community_tool` for architectural groupings

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

Scan manually ONLY for what CRG's code graph cannot provide:

- Domain docs, ADRs, README context relevant to the task
- SAM/CloudFormation templates for infrastructure relationships (Lambda -> DynamoDB -> EventBridge)
- `.instructions.md` and `AGENTS.md` conventions in each relevant repo
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

### 6. Fallback (CRG Unavailable)

If CRG is not available (mode: off, graph not built, or tools not responding):

1. Fall back to manual multi-pass repo scanning:
   - Directory scan for structure
   - Targeted reads based on task description keywords
   - Test pattern discovery
2. Still write a tiered context bundle, but mark `source: manual` on all entries
3. Set `confidence: low` in the frontmatter
4. Add to Open Questions: "CRG graph not available — context may be incomplete. Run `/code-review-graph:build-graph` and re-curate."

## Guidelines

- Token economy matters — keep bundles scannable, not exhaustive
- Every non-obvious claim must be backed by evidence or labeled as inference
- Prefer `path + symbol + anchor_text` over path alone for resilient references
- If the task spans multiple repos, produce one unified bundle (not per-repo)
- If the bundle exceeds ~200 lines, move detail into an annex file: `context-bundle-{task-id}.annex.md`
