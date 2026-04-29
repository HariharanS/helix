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
4. Read [`cli-workflow.md`](./cli-workflow.md) when operating from Copilot CLI — defines the CLI-first phase playbook and which agents to invoke at each phase
5. Read [`trace-schema.md`](./trace-schema.md) and [`copilot-session-overlay-plan.md`](./copilot-session-overlay-plan.md) when changing session traces, hooks, or Copilot CLI Lens overlay behavior
6. Read only the specific guide relevant to the task
7. Do not use `docs/` as the default source for implementation details when a workspace artifact, execution plan, or context bundle exists

## Writing Rules

- Keep long-form narrative here, not in root `AGENTS.md`
- Prefer one document per concern instead of giant omnibus docs
- Keep the Helix process canonical in `helix-process.md` instead of restating it across multiple docs
- Link to canonical artifact locations instead of duplicating their contents
