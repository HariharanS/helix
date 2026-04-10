# scripts AGENTS Guide

This directory contains helper scripts and hook implementations.

## What Lives Here

- `setup-workspace.sh` — helper for workspace setup
- `hooks/` — lifecycle hook implementations

## Read Order

1. Read [`../AGENTS.md`](../AGENTS.md) for repo-level rules
2. Read the specific script you intend to change
3. If working on hooks, also inspect [`../hooks/hooks.json`](../hooks/hooks.json)

## Editing Rules

- Keep scripts narrow in scope and explicit about inputs and outputs
- Do not let scripts silently redefine the documented workspace model
- If script behavior changes artifact structure, update the corresponding docs and templates
