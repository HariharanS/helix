---
name: onboard
description: Makes a repository agent-ready — explores structure, generates AGENTS.md, discovers coding patterns, and creates .instructions.md files
argument-hint: "Path to the repo to onboard (e.g. '../service-a') or --refresh to update existing"
user-invocable: true
disable-model-invocation: true
---

# Onboard Skill

Makes a repository agent-ready by generating context documents and discovering reusable patterns.
Supports first-run onboarding and `--refresh` mode for incremental updates.

## Mode Detection

- **First run:** No AGENTS.md exists at repo root → full onboard
- **Refresh (`--refresh`):** AGENTS.md exists → re-scan, diff against existing, show changes for approval

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
   - IaC: `serverless.yml` or `template.yaml` (SAM), `cdk.json` (CDK), `*.tf` (Terraform), `serverless.yml`, `Pulumi.yaml`
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
6. **Test analysis:** Scan test directories
   - Test framework (discover from config/imports, don't assume)
   - Test patterns (naming, structure, fixtures, factories)
   - Test infrastructure (local emulators, mocks, fakes, containers)
7. **Git history:** Recent activity, active contributors, commit conventions

## Phase 2: Discover Patterns

For each repeating pattern found, classify it:

```markdown
| Pattern | Type | Frequency | Candidate Skill? |
|---------|------|-----------|-------------------|
| Handler/endpoint boilerplate | repo-specific | every endpoint | yes |
| CRUD operations for data store | cross-cutting | every entity | yes |
| Test setup with emulators | cross-cutting | every test class | maybe |
| API response formatting | repo-specific | every endpoint | maybe |
```

**Repo-specific patterns** → generate in `{repo}/.github/skills/`
**Cross-cutting patterns** → flag for addition to Helix universal skills

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

### 3d. Candidate Skills

For each pattern marked as "candidate skill":
- Generate `SKILL.md` with the pattern template
- Include one example extracted from the codebase
- Place in `{repo}/.github/skills/{name}/SKILL.md`

## Phase 4: Human Review

Present ALL generated artifacts for review. Do not commit anything without human approval.

Checklist:
- [ ] AGENTS.md accurately describes the service
- [ ] Architecture diagram matches reality
- [ ] Code conventions are correct (discovered, not assumed)
- [ ] Instruction files reflect actual patterns, not generic advice or duplicated context
- [ ] Instruction files are short, scoped, and only contain non-obvious rules
- [ ] Discovered skills are useful (not too trivial)
- [ ] No sensitive information in generated docs

After approval, commit all artifacts.

## Refresh Mode (`--refresh`)

When re-running on an already-onboarded repo:

1. Re-scan the repo (same as Phase 1)
2. Diff new findings against existing AGENTS.md and .instructions.md
3. Show changes for human approval:
   - New patterns discovered
   - Existing patterns that changed
   - Patterns that no longer exist
4. Update only changed files after approval
