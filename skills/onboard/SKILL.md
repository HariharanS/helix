---
name: onboard
description: Makes a repository agent-ready — explores structure, generates AGENTS.md, repo-profile, discovers coding patterns, and creates candidate skills
argument-hint: Path to the repo to onboard (e.g. "../service-a")
user-invocable: true
disable-model-invocation: true
---

# Onboard Skill

Makes a repository agent-ready by generating context documents and discovering reusable patterns.

## Phase 1: Explore

Read and analyze the repo structure:

1. **Entry points:** Read README.md, any existing documentation
2. **Infrastructure:** Parse `template.yaml` (SAM template)
   - Extract all Lambda functions (name, handler, runtime, events)
   - Extract DynamoDB tables (name, key schema, GSIs)
   - Extract S3 buckets, EventBridge rules, SQS queues
   - Extract API Gateway routes (path, method, function mapping)
   - Extract IAM permissions (what each function can access)
3. **Code structure:** Parse `.csproj` / solution files
   - Project dependencies (NuGet packages)
   - Project structure (folders, namespaces)
4. **Source code:** Scan `src/` directory
   - Identify folder conventions (Domain/, Infrastructure/, Contracts/, Functions/)
   - Identify base classes, shared interfaces
   - Identify DI/dependency injection patterns
   - Identify error handling patterns (exceptions vs Result pattern)
   - Identify logging patterns
5. **Tests:** Scan test directories
   - Test framework (xUnit, NUnit, MSTest)
   - Test patterns (naming, structure, fixtures)
   - Test infrastructure (local DynamoDB, mocks, fakes)
6. **Git history:** Recent activity, active contributors

## Phase 2: Discover Patterns

For each repeating pattern found, classify it:

```markdown
| Pattern | Type | Frequency | Candidate Skill? |
|---------|------|-----------|-------------------|
| Lambda handler boilerplate | repo-specific | every function | yes: scaffold-lambda |
| DynamoDB CRUD operations | cross-cutting | every repo | yes: scaffold-dynamo |
| Test setup with local DDB | cross-cutting | every test class | yes: scaffold-test |
| API response formatting | repo-specific | every endpoint | maybe |
```

**Repo-specific patterns** → generate in `service-repo/.github/skills/`
**Cross-cutting patterns** → flag for addition to `helix/skills/`

## Phase 3: Synthesize

Generate these artifacts:

### 3a. Root AGENTS.md

Place at repo root. Include:
- Service purpose (from README + code analysis)
- Service boundary diagram (mermaid, from SAM template)
- Inbound/outbound connections
- AWS resources owned
- Repo structure tree with annotations
- Key conventions discovered
- Build/test/deploy instructions

### 3b. Code-level AGENTS.md

Place at `src/AGENTS.md`. Include:
- Project structure (layers, folders, namespaces)
- Domain model overview (entities, key interfaces)
- DynamoDB access patterns (PK/SK for each entity)
- Key abstractions and base classes
- Test patterns and conventions

### 3c. Repo Profile

Place at `.copilot/repo-profile.md`. Machine-generated:
- Annotated file tree
- Dependency graph
- Entity/access pattern map
- Lambda function inventory
- Last updated timestamp

### 3d. Candidate Skills

For each pattern marked as "candidate skill":
- Generate `SKILL.md` with the pattern template
- Include one example extracted from the codebase
- Place in `.github/skills/{name}/SKILL.md`

## Phase 4: Human Review

Present ALL generated artifacts for review. Do not commit anything without human approval.

Checklist:
- [ ] AGENTS.md accurately describes the service
- [ ] Service boundary diagram matches reality
- [ ] Code conventions are correct
- [ ] Discovered skills are useful (not too trivial)
- [ ] No sensitive information in generated docs

After approval, commit all artifacts.
