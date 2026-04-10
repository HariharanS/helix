# scripts AGENTS Guide

This directory contains helper scripts and hook implementations.

## What Lives Here

- `install-helix.ps1` — materializes Helix into a meta repo
- `set-context-provider.ps1` — enables or disables optional context providers such as code-review-graph
- `sync-helix.ps1` — re-syncs managed Helix files from core into the meta repo
- `setup-workspace.ps1` — attaches selected repos for a workspace and generates the `.code-workspace` file
- `doctor.ps1` — validates manifests and readiness
- `Helix.Tools.psm1` — shared manifest and path helpers
- `setup-workspace.sh` — legacy helper for the pre-split combined layout
- `hooks/` — lifecycle hook implementations

## Read Order

1. Read [`../AGENTS.md`](../AGENTS.md) for repo-level rules
2. Read the specific script you intend to change
3. If working on hooks, also inspect [`../hooks/hooks.json`](../hooks/hooks.json)

## Editing Rules

- Keep scripts narrow in scope and explicit about inputs and outputs
- Do not let scripts silently redefine the documented workspace model
- If script behavior changes artifact structure, update the corresponding docs and templates
- Prefer the PowerShell runtime scripts over the legacy Bash helper for the target meta-repo model
