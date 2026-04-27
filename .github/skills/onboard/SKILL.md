---
name: onboard
managed-by: helix-core
description: Makes a repository agent-ready — explores structure, generates AGENTS.md, discovers coding patterns, and creates .instructions.md files
argument-hint: "Path to the repo to onboard (e.g. '../service-a') or --refresh to update existing"
user-invocable: true
disable-model-invocation: true
---

# Onboard Skill

Makes a repository agent-ready by generating context documents and discovering reusable patterns.
Supports first-run onboarding and `--refresh` mode for incremental updates.

## Formatting Rules

- Use blank lines between all markdown sections and list items
- SKILL.md files must have the YAML frontmatter block as the very first content
- Prefer bullet lists and short tables over prose paragraphs

## Mode Detection

- **First run:** No AGENTS.md exists at repo root → full onboard
- **Refresh (`--refresh`):** AGENTS.md exists → re-scan, diff against existing, show changes for approval

## Phase 0: Pre-flight

Before exploring the target repo, orient yourself using existing platform context.

1. **Read meta-repo platform skills:** Scan `{meta-repo}/.github/skills/` for existing product/platform skills. Ignore Helix system skill folders (`onboard`, `workspace-sync`, `curate-context`, `distill`, `maker`, `refactor`, `skill-synth`, `task-board`, `tdd-cycle`). Note any product patterns already captured — do not duplicate them in this repo's skills.
2. **Read workspace platform doc:** If `workspaces/{name}/AGENTS.md` exists, read it for platform-level architecture context. Use it to inform cross-repo connection descriptions in this repo's AGENTS.md.
3. **Resolve workspace:** Determine the active workspace from `.helix/active-workspace.yml`. If running with only a repo path and no workspace context available, skip step 2 — mark workspace AGENTS.md as unknown and continue.

Phase 0 must not block onboarding. If meta-repo or workspace context is unavailable, proceed directly to Phase 1.

## Phase 1: Explore

Read and analyze the repo structure. Detect everything dynamically — never assume a tech stack.

1. **Entry points:** Read README.md, any existing documentation
2. **Language detection:** Look for manifest files:
   - `package.json` → Node.js/TypeScript
   - `*.csproj` / `*.sln` → .NET/C#
   - `go.mod` → Go
   - `requirements.txt` / `pyproject.toml` / `Pipfile` → Python
   - `Cargo.toml` → Rust
   - `pom.xml` / `build.gradle` → Java/Kotlin
3. **Framework detection:** Look for:
   - IaC: `serverless.yml` or `template.yaml` (SAM), `cdk.json` (CDK), `*.tf` (Terraform), `Pulumi.yaml`
   - Web: `next.config.*`, `angular.json`, `vite.config.*`, `nuxt.config.*`
   - API: `openapi.*`, `swagger.*`, route/controller directories
4. **Infrastructure inventory:** Parse IaC files for:
   - Compute resources (functions, containers, services)
   - Data stores (databases, caches, queues, storage)
   - API routes and event sources
   - Permissions and access patterns
5. **Code structure:** Scan source directories
   - Folder conventions and layer separation
   - Base classes, shared interfaces, abstractions
   - Dependency injection patterns
   - Error handling patterns (exceptions, Result types, error codes)
   - Logging patterns
6. **Test and verification analysis:** Scan test directories and CI configuration
   - Test framework (discover from config/imports, don't assume)
   - Test patterns (naming, structure, fixtures, factories)
   - Test infrastructure (local emulators, mocks, fakes, containers)
   - Available verification commands: focused test filter, full suite, integration/e2e, linting — read from `Makefile`, `package.json scripts`, `.github/workflows/*.yml`, or equivalent CI config
   - Flag commands that require a special environment (CI-only, cloud deploy, emulator) as `environment-gated`
7. **Git history:** Recent activity, active contributors, commit conventions

## Phase 2: Discover Patterns

For each repeating pattern found, classify it and assign a destination:

```markdown
| Pattern | Type | Frequency | Destination |
|---------|------|-----------|-------------|
| Handler/endpoint boilerplate | repo-specific | every endpoint | repo-skill |
| Response<T> railway result | cross-cutting | every service | meta-repo-candidate |
| DynamoDB key prefix helpers | cross-cutting | every repository | meta-repo-candidate |
| Test setup with local emulators | cross-cutting | every test class | meta-repo-candidate |
| API response formatting | repo-specific | every endpoint | repo-skill |
```

**Destination values:**
- `repo-skill` → generate in `{repo}/.github/skills/` (Phase 3d)
- `meta-repo-candidate` → do NOT generate a repo skill; include in the cross-cutting promotion table (Phase 3e)
- `flag-only` → note the pattern but skip skill generation (too trivial or already well-covered)

**Cross-cutting gate:** Only mark `meta-repo-candidate` when the pattern:
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
- Architecture diagram (mermaid, from IaC + code structure)
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

### 3c. Instruction Files

Generate `.github/instructions/{topic}.instructions.md` ONLY for major convention areas that are both recurring and non-obvious:
- Language conventions (naming, formatting, idioms)
- Data store conventions (query patterns, schema patterns)
- IaC conventions (resource naming, configuration patterns)
- Testing conventions (framework, patterns, infrastructure)

Each instruction file should be:
- Specific to THIS repo (not generic best practices)
- Discovered from actual code patterns (not assumed)
- Actionable for an AI agent (not documentation for humans)
- Narrowly scoped with an `applyTo` glob that targets the relevant files
- Short: usually 5-8 bullets, never a long essay
- Limited to non-obvious repo rules that an agent would otherwise miss
- Evidence-backed — every rule should be traceable to existing code, config, or tests

Do NOT put these into instruction files:
- Generic language/framework advice
- Architecture overviews
- Domain glossary content
- Requirements or feature-specific context
- Anything already covered adequately by root `AGENTS.md`

### 3d. Repo Skills

For each pattern with `Destination: repo-skill`:

- Generate `{repo}/.github/skills/{name}/SKILL.md`
- Include one real example extracted from the codebase

**Every SKILL.md must begin with this YAML frontmatter block (all five keys are required):**

```yaml
---
name: {folder-name}
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
- Runtime capability files are generated later by `workspace-sync` / `setup-workspace.ps1`; do not claim this skill writes `.helix/repo-state` or `.helix/repo-capabilities` directly

### 3e. Cross-Cutting Promotion Table

At the end of your output, append this section listing all `meta-repo-candidate` patterns.
Do NOT generate repo-level skills for these.

```markdown
## Cross-Cutting Patterns — Candidates for Meta-Repo Promotion

| Pattern | Evidence (file + symbol) | Repos seen in | Suggested skill name |
|---------|--------------------------|---------------|----------------------|
| Response<T> railway result | `Core/Services/FooService.cs: IFooService` | PaymentRequest, Tokens | `response-railway` |
| DynamoDB key prefix helpers | `Core/Extensions/DbKeyPrefixExtensions.cs` | Tokens, CustomerResources | `dynamodb-key-prefix` |
```

This table is consumed by the setup agent's Step 6c. Present it for human review — do not create meta-repo skills unilaterally.

## Phase 4: Human Review

Present ALL generated artifacts for review. Do not commit anything without human approval.

Checklist:
- [ ] AGENTS.md accurately describes the service
- [ ] Architecture diagram matches reality
- [ ] Code conventions are correct (discovered, not assumed)
- [ ] Instruction files reflect actual patterns, not generic advice or duplicated context
- [ ] Instruction files are short, scoped, and only contain non-obvious rules
- [ ] Every SKILL.md has correct YAML frontmatter (name, managed-by: helix-runtime, description, argument-hint, user-invocable)
- [ ] Cross-cutting patterns are in the promotion table, not duplicated as repo-level skills
- [ ] Discovered skills are useful (not too trivial)
- [ ] Verification policy commands are discovered from actual repo config, not invented
- [ ] Environment-gated commands are flagged with explicit reason
- [ ] No sensitive information in generated docs

After approval, commit all artifacts.

## Refresh Mode (`--refresh`)

When re-running on an already-onboarded repo:

1. Re-scan the repo (same as Phase 1 and Phase 0)
2. Diff new findings against existing AGENTS.md and `.instructions.md`
3. Diff existing `.github/skills/*/SKILL.md` against discovered patterns:
   - Skills whose patterns no longer exist → propose deletion
   - Skills that should be promoted to meta-repo → propose migration (delete repo skill, add to promotion table)
   - New patterns not yet covered → propose new skills
4. Show all changes for human approval:
   - New patterns discovered
   - Existing patterns that changed or no longer exist
   - Skills to add, delete, or migrate to meta-repo
5. Update only changed files after approval
