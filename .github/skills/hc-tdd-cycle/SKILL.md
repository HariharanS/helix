---
name: hc-tdd-cycle
managed-by: helix-core
description: Runs a complete TDD red-green-refactor cycle for a single task — writes failing tests, implements, refactors, and commits
argument-hint: Task ID and description (e.g. "TASK-001 implement GetOrderHistory")
user-invocable: true
disable-model-invocation: true
---

# TDD Cycle Skill

Runs a complete red-green-refactor cycle for a single task. This is a standalone user-invocable skill, not part of the orchestrated agent flow (the hc-implementer agent runs its own TDD cycle internally).

## Workflow

```
1. READ TASK — Parse the task ID and acceptance criteria
2. GATHER CONTEXT — Read AGENTS.md, relevant code patterns, test patterns
3. RED — Write failing tests matching each AC
   - Follow repo test conventions
   - Run tests — must fail
4. GREEN — Write minimal implementation
   - Follow repo code conventions
   - Run tests — must pass
5. REFACTOR — Improve quality
   - Only touch code you just wrote
   - Run tests — must still pass
6. FULL SUITE — Run all tests
   - If regressions: fix or report
7. COMMIT — Descriptive commit message
   - Format: feat(TASK-XXX): description
```

## Pre-requisites

- Task has clear acceptance criteria
- Repo has existing test infrastructure
- AGENTS.md exists with coding conventions

## Error Recovery

- Test fails after 3 attempts → stop, report blocker, don't rollback
- Anchor point not found → search for updated location
- Full suite regression → report but continue if your tests pass
