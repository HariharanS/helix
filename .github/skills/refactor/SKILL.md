---
name: refactor
managed-by: helix-core
description: Applies cross-cutting refactoring patterns from memory and conventions across a codebase
argument-hint: "Describe the refactoring (e.g. 'apply error handling pattern from learnings', 'standardize API response format')"
user-invocable: true
disable-model-invocation: true
---

# Refactor Skill

Applies consistent patterns across a codebase, informed by Helix memory learnings and repo conventions. This is a standalone user-invocable skill, not part of the orchestrated agent flow.

## Workflow

### 1. Understand the Pattern

- Read the refactoring request
- Search `.helix/memory/learnings/` for relevant patterns
- Read root and nested AGENTS.md files in the target repo for conventions
- Identify the "before" pattern and the "after" pattern

### 2. Scope the Change

Search the codebase for all instances of the "before" pattern:

```markdown
# Refactoring Scope: {pattern name}

| File | Line(s) | Current Pattern | Change Required |
|------|---------|-----------------|-----------------|
| path/to/file1 | 23-30 | old pattern | description |
| path/to/file2 | 45-52 | old pattern | description |
```

Present the scope for approval before making changes.

### 3. Apply Changes

For each instance:
1. Apply the "after" pattern
2. Run tests after each file (fail-fast)
3. If tests break, stop and report

### 4. Verify

- Run full test suite
- Report results: how many instances changed, how many tests pass/fail
- If any regressions, identify which change caused it

## Guidelines

- Always scope before applying — never refactor blindly
- Present the full change scope for human approval
- Apply one pattern at a time (don't combine multiple refactorings)
- Run tests after each file change, not just at the end
- If a pattern instance doesn't quite match (edge case), skip it and flag for manual review
- Follow the repo's conventions — don't impose external patterns
- Check `.helix/memory/learnings/` for context on WHY the pattern exists
- Commit with a descriptive message: `refactor: {pattern description}`

## Error Recovery

- Test failure after change → revert that file, report the exception
- Pattern doesn't match cleanly → skip, add to "manual review needed" list
- Too many instances (>50) → ask if the user wants to proceed in batches
