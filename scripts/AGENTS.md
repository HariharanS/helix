# scripts AGENTS Guide

This directory contains helper scripts and hook implementations.

## What Lives Here

- `init.ps1` — user-facing wrapper for future `helix init`
- `sync.ps1` — user-facing wrapper for future `helix sync`
- `upgrade.ps1` — user-facing wrapper for future `helix upgrade`
- `workspace-setup.ps1` — user-facing wrapper for future `helix workspace setup`
- `init-meta-repo.ps1` — bootstrap implementation behind `init.ps1`
- `install-helix.ps1` — materializes Helix into a meta repo
- `set-context-provider.ps1` — configures code-review-graph mode and MCP entries; `off` is emergency fallback only
- `sync-helix.ps1` — sync implementation behind `sync.ps1` and `upgrade.ps1`
- `setup-workspace.ps1` — workspace setup implementation behind `workspace-setup.ps1`
- `doctor.ps1` — validates manifests and readiness
- `Helix.Tools.psm1` — shared manifest and path helpers
- `setup-workspace.sh` — legacy helper for the pre-split combined layout
- `hooks/` — lifecycle hook implementations

## Read Order

1. Read [`../AGENTS.md`](../AGENTS.md) for repo-level rules
2. Read the specific script you intend to change
3. If working on hooks, inspect [`../.github/hooks/helix.json`](../.github/hooks/helix.json) and the runtime under [`../.github/hooks/scripts`](../.github/hooks/scripts)

## Editing Rules

- Keep scripts narrow in scope and explicit about inputs and outputs
- Do not let scripts silently redefine the documented workspace model
- If script behavior changes artifact structure, update the corresponding docs and templates
- Prefer the wrapper scripts as the documented entry points; keep the older implementation names backward-compatible
- Prefer the PowerShell runtime scripts over the legacy Bash helper for the target meta-repo model
