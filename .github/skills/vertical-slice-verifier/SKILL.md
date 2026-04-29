---
name: vertical-slice-verifier
managed-by: helix-core
description: Generate an integration-test scaffold from a slice's cross_repo_contracts. Emits the test shape (HTTP, event, schema migration) — operator wires the runner.
argument-hint: "Path to execution-plan.yaml plus slice id, e.g. workspaces/order-history/execution-plans/order-history.yaml SLICE-1"
user-invocable: true
disable-model-invocation: true
---

# Vertical Slice Verifier Skill

Reads a slice's `cross_repo_contracts` and emits a tech-agnostic integration test scaffold. The skill produces the *shape* of the test (request, expected response, event payload, schema fields). It does not pick a runner, ship a harness, or assume an ecosystem (Pact, OpenAPI, AsyncAPI, k8s, docker — none baked in).

## Workflow

### 1. Read inputs

- Read the execution plan at the supplied path
- Locate the slice by `id`; if the slice has no `cross_repo_contracts`, stop and report "no cross-repo work for this slice"
- Read each `cross_repo_contracts[].schema_path`; if a path is missing, mark the contract unresolved and continue with the others

### 2. Pick a template per contract

Match `cross_repo_contracts[].type` to a scaffold template:

- `http` — request/response shape (method + path, request body, expected status + response body, error cases)
- `event` — publish/consume shape (canonical payload, producer publish assertion, consumer handler outcome)
- `schema` — migration/compatibility shape (before fields, after fields, backward-compat assertions)
- anything else — generic Given/When/Then template (preconditions, action, expected outcome)

Do NOT bake in Pact, OpenAPI, AsyncAPI, container tooling, or any specific runner. The template names the surface; the operator fills in the executor.

### 3. Emit scaffold

For each contract, write `workspaces/{workspace}/verification/{slice-id}/{contract-name}.{type}.scaffold.md` containing:

- frontmatter: `slice_id`, `contract_name`, `version`, `producer`, `consumers`, `schema_path`
- a Given/When/Then block describing what the test must prove
- a `# RUNNER:` placeholder block the operator fills with the actual command, framework, or fixture wiring
- a one-line link back to `slices[].verification.integration.command` (if present) or each `verification.contract_tests` path

### 4. Update the slice (advisory)

Append a comment block to the slice in `execution-plan.yaml` listing the scaffold paths under `verification.contract_tests`. Do not overwrite operator-set entries; only append.

### 5. Report

Per contract:
- template used
- scaffold path
- whether `schema_path` resolved

Overall:
- count of scaffolds generated
- contracts requiring operator attention (unresolved schema, producer or consumer missing from `slices[].repos`)

## When to Use

- After decomposer emits an execution plan with `cross_repo_contracts`
- When adding a new cross-repo contract to an existing slice and you want a starting test shape

## Notes

- Scaffolds are *shapes*, not runnable tests. Operator must wire a runner before the slice gate fires
- This skill does not invoke `verification.integration.command` or any `contract_tests` — the implementer runs them at the slice gate
- Keep generated scaffolds short. If a contract needs more than ~40 lines of scaffold, the contract is doing too much — push back to architect
