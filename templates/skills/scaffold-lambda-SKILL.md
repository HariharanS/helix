---
name: scaffold-lambda
description: Scaffolds a new AWS Lambda function with handler, SAM template entry, and test file following repo conventions
argument-hint: Function name and HTTP method/event type (e.g. "GetOrderHistory GET /orders/history/{id}")
user-invocable: true
disable-model-invocation: false
---

# Scaffold Lambda Skill

Scaffolds a new Lambda function following the repo's established patterns.

## What Gets Created

1. **Lambda handler** in `src/Functions/{FunctionName}Function.cs`
2. **SAM resource** in `template.yaml`
3. **Test file** in `tests/{FunctionName}FunctionTests.cs`
4. **Interface method** (if extending an existing repository interface)

## Workflow

1. Read the repo's AGENTS.md for conventions
2. Find an existing Lambda function as the pattern source
3. Scaffold each file following the discovered pattern:
   - Handler: copy structure, change names, leave implementation as TODO
   - SAM: copy resource block, update function name, handler, path, method
   - Test: copy structure, set up basic arrange-act-assert skeleton
4. Present to user for review

## Guidelines

- Match existing naming exactly (casing, suffixes, namespaces)
- Match existing folder structure
- SAM template should follow the same resource ordering pattern
- Include minimal DI registration if the repo uses dependency injection
- Tests should compile and fail (red) — ready for TDD green phase
- Do NOT implement business logic — just the scaffolding
