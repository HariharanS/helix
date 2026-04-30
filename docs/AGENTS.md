# docs AGENTS Guide

This directory contains human-facing documentation.

## What Lives Here

- Usage guides
- Roadmap and design-direction documents
- Explanatory docs that are too long or narrative-heavy for `AGENTS.md`

## Read Order

1. Read [`../README.md`](../README.md) for the high-level product story
2. Read [`helix-process.md`](./helix-process.md) for the canonical lifecycle
3. Read [`helix-instance-schemas.md`](./helix-instance-schemas.md) when working on meta-repo manifests or installer behavior
4. Read [`agents-md-authoring.md`](./agents-md-authoring.md) when changing AGENTS.md generation, onboarding, or instruction-surface behavior
5. Read [`meta-repo-skills-management.md`](./meta-repo-skills-management.md) when changing onboarding-discovered skills, skill projection, or router behavior
6. Read [`hc-hr-runtime-surface-rename-plan.md`](./hc-hr-runtime-surface-rename-plan.md) before renaming agent, prompt, or skill runtime surfaces
7. Read [`cli-workflow.md`](./cli-workflow.md) when operating from Copilot CLI — defines the CLI-first phase playbook and which agents to invoke at each phase
8. Read [`trace-schema.md`](./trace-schema.md), [`copilot-session-overlay-plan.md`](./copilot-session-overlay-plan.md), and [`copilot-cli-hooks-and-env.md`](./copilot-cli-hooks-and-env.md) when changing session traces, hooks, Copilot environment handling, or Copilot CLI Lens overlay behavior
9. Read only the specific guide relevant to the task
10. Do not use `docs/` as the default source for implementation details when a workspace artifact, execution plan, or context bundle exists

## Writing Rules

- Keep long-form narrative here, not in root `AGENTS.md`
- Prefer one document per concern instead of giant omnibus docs
- Keep the Helix process canonical in `helix-process.md` instead of restating it across multiple docs
- Link to canonical artifact locations instead of duplicating their contents
