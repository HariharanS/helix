---
name: hc-onboard
managed-by: helix-core
description: Makes a repository agent-ready — uses CRG-first repo discovery, generates AGENTS.md guidance, and discovers coding patterns
argument-hint: "Path to the repo to onboard (e.g. '../service-a') or --refresh to update existing"
user-invocable: true
disable-model-invocation: true
---

# Onboard Skill

Makes a repository agent-ready by generating context documents and discovering reusable patterns.
Supports first-run onboarding and `--refresh` mode for incremental updates.
Follow `helix/docs/agents-md-authoring.md` for root vs nested AGENTS.md layering and size rules.

## Formatting Rules

- Use blank lines between all markdown sections and list items
- SKILL.md files must have the YAML frontmatter block as the very first content
- Prefer bullet lists and short tables over prose paragraphs

## Mode Detection

- **First run:** No AGENTS.md exists at repo root → full onboard
- **Refresh (`--refresh`):** AGENTS.md exists → re-scan, diff against existing, show changes for approval

## Retrieval Contract

- Read `.helix/context-providers.yml` before code discovery.
- If `code_review_graph.mode` is `mcp`, code-review-graph is the **primary** retrieval engine for code navigation, architecture discovery, symbol lookup, execution flows, and pattern hunting.
- In `mode: mcp`, a missing or empty graph is a **hard setup error**. Stop and surface the repair step; do not silently fall back to recursive source scans, repo-wide grep, or generic `search/codebase` probing.
- In `mode: mcp`, manual reads are still expected for README/docs, manifests, IaC, CI config, and other non-code artifacts that CRG does not model well.
- Manual multi-pass repo scanning is allowed only when `code_review_graph.mode` is explicitly `off`.

## Phase 0: Pre-flight

Before exploring the target repo, orient yourself using existing platform context.

1. **Read meta-repo platform skills:** Scan `{meta-repo}/.github/skills/` for existing product/platform skills. Ignore Helix system skill folders (`hc-build-graph`, `hc-curate-context`, `hc-maker`, `hc-onboard`, `hc-playwright-cli`, `hc-refactor`, `hc-review-delta`, `hc-review-pr`, `hc-skill-synth`, `hc-task-board`, `hc-tdd-cycle`, `hc-vertical-slice-verifier`, `hc-workspace-sync`). Note any product patterns already captured — do not duplicate them in this repo's skills.
2. **Read workspace platform doc:** If `workspaces/{name}/AGENTS.md` exists, read it for platform-level architecture context. Use it to inform cross-repo connection descriptions in this repo's AGENTS.md.
3. **Resolve workspace:** Determine the active workspace from `.helix/active-workspace.yml`. If running with only a repo path and no workspace context available, skip step 2 — mark workspace AGENTS.md as unknown and continue.
4. **Read context-provider config:** Read `.helix/context-providers.yml` and record `code_review_graph.mode`. If the file is missing, stop and tell the operator to complete or re-run `helix/scripts/workspace-setup.ps1` / `hc-setup` before onboarding.

Phase 0 must not block onboarding when only workspace context is unavailable. Missing CRG/provider config is a setup error and should stop the run.

## Phase 1: Explore

Read and analyze the repo structure. Detect everything dynamically — never assume a tech stack.

1. **CRG readiness probe (`mode: mcp` only):**
   - Determine the repo path being onboarded.
   - Run `python -m code_review_graph status --repo {repo-path}` (or the configured CRG runner if setup installed a different wrapper).
   - Exit 0 and `nodes > 0` → proceed with graph-first retrieval.
   - Exit non-zero or `nodes = 0` → **HARD ERROR**. Stop and surface exact remediation:

     > CRG is configured as `mode: mcp` in `.helix/context-providers.yml`, but the graph for `{repo-path}` is unavailable. Re-run `helix/scripts/workspace-setup.ps1 -Workspace {name}` or `/hc-build-graph full`, then retry onboarding. To continue without graph-based retrieval, explicitly set `mode: off`.

   - Do **not** continue to manual scanning in `mode: mcp`.
2. **Graph-first repo map (`mode: mcp`):** Use CRG first to understand the repo before reading code manually:
   - `get_minimal_context_tool(task="onboard repo {repo-name}")`
   - `get_architecture_overview_tool`
   - `list_communities_tool` and `get_community_tool` for major modules / bounded contexts
   - `list_flows_tool` and `get_flow_tool` for entry points and critical execution paths
   - `semantic_search_nodes_tool` and `query_graph_tool` for handlers, services, repositories, tests, shared abstractions, and likely convention hotspots
   - Use the configured `detail_level` from `.helix/context-providers.yml`; do not hardcode a level here.
3. **Entry points and docs:** Read README.md, existing docs, and any existing `AGENTS.md` files. Use these to interpret the graph, not replace it.
4. **Language detection:** Look for manifest files:
   - `package.json` → Node.js/TypeScript
   - `*.csproj` / `*.sln` → .NET/C#
   - `go.mod` → Go
   - `requirements.txt` / `pyproject.toml` / `Pipfile` → Python
   - `Cargo.toml` → Rust
   - `pom.xml` / `build.gradle` → Java/Kotlin
5. **Framework detection:** Look for:
   - IaC: `serverless.yml` or `template.yaml` (SAM), `cdk.json` (CDK), `*.tf` (Terraform), `Pulumi.yaml`
   - Web: `next.config.*`, `angular.json`, `vite.config.*`, `nuxt.config.*`
   - API: `openapi.*`, `swagger.*`, route/controller directories
6. **Infrastructure inventory:** Parse IaC files for:
   - Compute resources (functions, containers, services)
   - Data stores (databases, caches, queues, storage)
   - API routes and event sources
   - Permissions and access patterns
7. **Code structure:** Inspect the code areas surfaced by CRG plus the minimum supporting files needed to understand them. Do not start with recursive source-tree scans or repo-wide grep.
   - Folder conventions and layer separation
   - Base classes, shared interfaces, abstractions
   - Dependency injection patterns
   - Error handling patterns (exceptions, Result types, error codes)
   - Logging patterns
8. **Test and verification analysis:** Inspect test directories, CI configuration, and CRG-discovered tests/flows
   - Test framework (discover from config/imports, don't assume)
   - Test patterns (naming, structure, fixtures, factories)
   - Test infrastructure (local emulators, mocks, fakes, containers)
   - Available verification commands: focused test filter, full suite, integration/e2e, linting — read from `Makefile`, `package.json scripts`, `.github/workflows/*.yml`, or equivalent CI config
   - Flag commands that require a special environment (CI-only, cloud deploy, emulator) as `environment-gated`
9. **Git history:** Recent activity, active contributors, commit conventions
10. **Emergency manual fallback (`mode: off` only):** If `code_review_graph.mode` is explicitly `off`, replace Step 2 with manual multi-pass scanning. Mark source-derived conclusions as lower-confidence and state explicitly that CRG was disabled. Do not use this branch when the `mode: mcp` probe fails.

## Phase 2: Discover Patterns

Base pattern candidates on CRG-discovered symbols/usages plus targeted file reads from Phase 1. Do not treat blind grep counts or repo-wide search alone as sufficient evidence for a pattern.

For each repeating pattern found, classify it and assign a destination:

```markdown
| Pattern | Type | Frequency | Destination |
|---------|------|-----------|-------------|
| Handler/endpoint boilerplate | repo-specific | every endpoint | repo-skill |
| Request/response adapter wrapper | cross-cutting | multiple modules | workspace-review |
| Shared integration harness bootstrap | cross-cutting | every integration test area | workspace-review |
| Repeated environment bootstrap config | cross-cutting | multiple deployable areas | workspace-review |
| API response formatting | repo-specific | every endpoint | repo-skill |
```

**Destination values:**
- `repo-skill` → generate in `{repo}/.github/skills/` (Phase 3d)
- `workspace-review` → do NOT generate a repo skill; include in the reusable-pattern table for later `hc-skill-synth` review (Phase 3e)
- `flag-only` → note the pattern but skip skill generation (too trivial or already well-covered)

**Cross-cutting gate:** Only mark `workspace-review` when the pattern:
- Appears in this repo AND is likely present in 1+ sibling repos based on Phase 0 findings
- Has consistent parameterization across usages
- Is not already captured in an existing meta-repo skill (Phase 0 check)

## Phase 3: Synthesize

Generate these artifacts in the target repo:

### 3a. Root AGENTS.md

Place at repo root. Include:
- Service/project purpose (from README + code analysis)
- Business capabilities and owned domain area
- Domain glossary for non-obvious business terms
- Architecture diagram (mermaid, from CRG structure, IaC, and targeted code analysis)
- Inbound/outbound connections
- Infrastructure resources owned
- Repo structure tree with annotations
- Key conventions discovered
- Build/test/deploy instructions

Keep root `AGENTS.md` concise:
- Prefer bullet lists, short tables, and annotated trees over prose blocks
- Include only non-obvious glossary terms and major owned boundaries
- Move deep inventories or exhaustive resource lists to appendices/annex files only if needed

### 3b. Code-level AGENTS.md

Place at `src/AGENTS.md` (or equivalent source root). Include:
- Project structure (layers, folders, namespaces/packages)
- Domain model overview (entities, key interfaces)
- Domain invariants and state transitions that are visible in code/tests
- Data access patterns
- Key abstractions and base classes
- Test patterns and conventions

### 3c. Specialized Nested AGENTS.md

Generate additional nested `AGENTS.md` files ONLY for major convention areas that are both recurring and non-obvious:
- `tests/AGENTS.md` or equivalent when test conventions differ from source conventions
- `infra/AGENTS.md`, `cdk/AGENTS.md`, or equivalent for IaC conventions
- generated-code subtree `AGENTS.md` when a folder has special editing constraints
- feature or module subtree `AGENTS.md` only when it prevents repeated mistakes

Each nested `AGENTS.md` should be:
- Specific to THIS repo (not generic best practices)
- Discovered from actual code patterns (not assumed)
- Actionable for an AI agent (not documentation for humans)
- Short: usually 5-8 bullets, never a long essay
- Limited to non-obvious repo rules that an agent would otherwise miss
- Evidence-backed — every rule should be traceable to existing code, config, or tests

Do NOT put these into nested `AGENTS.md` files:
- Generic language/framework advice
- Architecture overviews
- Domain glossary content
- Requirements or feature-specific context
- Anything already covered adequately by root `AGENTS.md`

### 3d. Repo Skills

For each pattern with `Destination: repo-skill`:

- Generate `{repo}/.github/skills/{name}/SKILL.md`
- Include one real example extracted from the codebase
- Treat generated repo skills as registry candidates. They are not guaranteed invokable from the meta-root until `hc-workspace-sync` indexes them and a later projection flow creates an approved `hr-*` skill.

**Every SKILL.md must begin with this YAML frontmatter block (all five keys are required):**

```yaml
---
name: {name}
managed-by: helix-runtime
description: {one-line description — first meaningful sentence about what the skill does}
argument-hint: "{short practical hint, e.g. 'Name of the new endpoint (e.g. CancelOrder)'}"
user-invocable: true
---
```

Notes on frontmatter:
- `name` must match the folder name exactly
- `managed-by: helix-runtime` marks this as generated by helix during project onboarding — never synced back to helix-core
- Do not add `disable-model-invocation` — that key is reserved for meta-level Helix skills only
- All five keys are required; do not omit any

### 3f. Verification Notes

Summarise discovered verification conventions in the root AGENTS.md under a **Verification** section and emit a short operator note for workspace-level follow-up.

Capture:
- likely focused-test and full-suite entry points when they are discoverable from the repo
- higher layers such as harness, sandbox, integration, UI, or release qualification when the repo clearly participates in them
- environment constraints (local emulator, cloud credentials, deployed env, CI-only runner)

Rules:
- Every command or hint must be discoverable from the actual repo (Makefile, CI config, package.json scripts, project file)
- Do NOT invent or guess commands — if a command cannot be verified, mark it as unknown or note the layer without a command
- Flag any command that requires a local emulator, cloud credentials, or specific CI runner as environment-gated with an explicit reason
- Runtime capability files are generated later by `hc-workspace-sync` / `setup-workspace.ps1`; do not claim this skill writes `.helix/repo-state` or `.helix/repo-capabilities` directly

### 3e. Reusable Pattern Candidates

At the end of your output, append this section listing all `workspace-review` patterns.
Do NOT generate repo-level skills for these.

```markdown
## Reusable Pattern Candidates

| Pattern | Evidence (file + symbol) | Likely scope | Parameterization notes |
|---------|--------------------------|--------------|-----------------------|
| Request/response adapter wrapper | `src/api/OrderHandler.ts: mapOrderResponse` | workspace-review | Varies by DTO pair and error mapping rules |
| Integration harness bootstrap | `tests/support/HarnessBuilder.ts: createHarness` | workspace-review | Inputs are environment, fixtures, and service doubles |
```

This table is consumed by the setup/workspace review flow. Present it for human review, and route promising candidates through `hc-skill-synth` before any projection or meta-root skill creation.

## Phase 4: Human Review

Present ALL generated artifacts for review. Do not commit anything without human approval.

Checklist:
- [ ] AGENTS.md accurately describes the service
- [ ] Architecture diagram matches reality
- [ ] Code conventions are correct (discovered, not assumed)
- [ ] Nested AGENTS.md files reflect actual patterns, not generic advice or duplicated context
- [ ] Nested AGENTS.md files are short, scoped, and only contain non-obvious rules
- [ ] Every SKILL.md has correct YAML frontmatter (name, managed-by: helix-runtime, description, argument-hint, user-invocable)
- [ ] Cross-cutting patterns are in the promotion table, not duplicated as repo-level skills
- [ ] Discovered skills are useful (not too trivial)
- [ ] Verification policy commands are discovered from actual repo config, not invented
- [ ] Environment-gated commands are flagged with explicit reason
- [ ] No sensitive information in generated docs

After approval, commit all artifacts.

## Refresh Mode (`--refresh`)

When re-running on an already-onboarded repo:

1. Re-scan the repo using the same CRG-first retrieval contract from Phase 0 and Phase 1
2. Diff new findings against existing root and nested AGENTS.md files
3. Diff existing `.github/skills/*/SKILL.md` against discovered patterns:
   - Skills whose patterns no longer exist → propose deletion
   - Skills that should be promoted to meta-repo → propose migration (delete repo skill, add to promotion table)
   - New patterns not yet covered → propose new skills
4. Show all changes for human approval:
   - New patterns discovered
   - Existing patterns that changed or no longer exist
   - Skills to add, delete, or migrate to meta-repo
5. Update only changed files after approval
