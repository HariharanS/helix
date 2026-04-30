---
name: hc-workspace-sync
managed-by: helix-core
description: Validates a repo registry, optionally seeds a workspace manifest from repo ids, runs the script-owned workspace setup flow, verifies outcomes, and then handles optional follow-on setup work
argument-hint: "Workspace name or path to workspace.yml; optionally include repo ids for -ReposCsv"
user-invocable: true
disable-model-invocation: true
---

# Workspace Sync Skill

Uses the script-owned workspace setup path once Helix is installed and the user has updated `helix-repos.yml`. Normal setup requires CRG MCP (`code_review_graph.mode: mcp`) and builds graphs for the selected repos; `mode: off` is an explicit emergency fallback.

If `workspaces/{name}/workspace.yml` is missing and the user supplies explicit repo ids, pass those ids to `helix/scripts/workspace-setup.ps1 -ReposCsv` so the script seeds the manifest. Do not hand-write the workspace manifest in this skill.
When evaluating AGENTS.md guidance or onboarding follow-up, use `helix/docs/agents-md-authoring.md`.

## Workflow

### 1. Confirm Helix Is Installed

- Check for `.helix/install-state.yml`, `helix-repos.yml` (or legacy `repos.yml`), `.helix/context-providers.yml`, and `helix/scripts/workspace-setup.ps1`
- If bootstrap is missing, stop and tell the user to run `init-meta-repo.ps1` from the Helix source checkout first
- Do not try to install Helix from this skill
- Normal bootstrap configures CRG MCP in `.vscode/mcp.json` and `~/.copilot/mcp-config.json`

### 2. Validate The Registry And Workspace Inputs

`helix-repos.yml` is the canonical instance-owned registry file created during installation from `helix/templates/helix-repos.yml.template`. `repos.yml` remains the legacy compatibility alias. The workspace manifest lives at `workspaces/{name}/workspace.yml`.

```
helix-repos.yml
workspaces/{name}/workspace.yml
```

Before setup:

- ensure `helix-repos.yml` (or legacy `repos.yml`) contains real repo definitions rather than sample placeholder values
- if the workspace manifest exists, ensure every `workspace.repos[*].repo_id` resolves to a registry entry
- if the workspace manifest is missing, require explicit repo ids and validate each id against the registry
- if the registry is missing or still needs edits, pause and ask the user to update it before continuing
- if the workspace manifest is missing and repo ids were not supplied, point to the installed root `README.md` Start Here section

Registry example:
```yaml
repos:
  - id: service-a
    remote: https://github.com/your-org/service-a
    local_path: ../service-a
    default_branch: main
  - id: service-b
    remote: https://github.com/your-org/service-b
    local_path: ../service-b
    default_branch: main
```

Workspace example:
```yaml
id: order-history
description: Order history feature spanning service-a and service-b
status: active
repos:
  - repo_id: service-a
    role: primary
  - repo_id: service-b
    role: dependency
```

### 3. Run The Authoritative Setup Script

Run `helix/scripts/workspace-setup.ps1` with the requested workspace name or manifest path.

- Pass `-ReposCsv` only when the workspace manifest is missing and the user supplied explicit repo ids
- Pass `-CloneMissing` only when the user wants missing workspace repos cloned locally
- Pass `-FetchExisting` only when the user wants already-present repos refreshed
- Pass `-IncludeClaudeSettings` only when Claude Desktop configuration is explicitly requested
- Do not pass `-SkipGraphBuild` while `code_review_graph.mode: mcp`; set CRG mode to `off` first if the user explicitly chose emergency no-CRG behavior
- Do not mutate `helix-repos.yml` or `repos.yml` from this skill
- Do not implement clone logic here; the script is the source of truth

### 4. Verify Definitive Outcomes

After `helix/scripts/workspace-setup.ps1` succeeds, verify:

- `{name}.code-workspace` exists at the meta-repo root
- `.helix/active-workspace.yml` points at the selected workspace
- `.helix/repo-state/{repo-id}.yml` exists for every repo in the workspace manifest
- `.helix/repo-capabilities/{repo-id}.yml` exists for every repo in the workspace manifest
- `.helix/skills/index.yml` exists and includes core skills plus repo-local candidates for onboarded repos
- `{name}.code-workspace` enables AGENTS.md and nested AGENTS.md loading settings
- the status table from the script reflects the expected presence and readiness values
- if `code_review_graph.mode: mcp`, CRG graph build succeeded for every present repo

Report status using the generated repo-state files as the source of truth.

### 5. Optional Follow-On Setup

Only after baseline workspace attach succeeds:

#### 5a. Onboard Repos

Run the `hc-onboard` skill for each repo marked `needs-onboarding` or `partial` in repo-state. In `code_review_graph.mode: mcp`, each onboard run must use CRG as the primary retrieval engine and fail hard if the target repo graph is unavailable — do not silently fall back to grep or generic code search. Run repos in parallel where possible. Each onboard run produces a **Reusable Pattern Candidates** table — collect these outputs.

#### 5b. Refresh Repo-State and Capability Files

After all onboarding completes, re-run `helix/scripts/workspace-setup.ps1 -Workspace {name}` with no additional flags. This re-scans all repos, updates repo-state signals (`root_agents`, `nested_agents`, `repo_skills`, `tests_present`), refreshes repo-capabilities, removes Helix-generated legacy `.instructions.md` summaries, and rebuilds CRG graphs when `mode: mcp`. Do NOT manually patch `.helix/repo-state/*.yml` or `.helix/repo-capabilities/*.yml` files.

After the script completes:
- verify `.helix/repo-capabilities/{repo-id}.yml` exists for each workspace repo
- verify `.helix/skills/index.yml` includes any repo-local `.github/skills/*/SKILL.md` as `candidate` entries
- treat those files as the generated source of truth for **abstract** capability hints:
  - language/build markers
  - discovered verification layers
  - whether a layer looks local-runnable, hybrid, or environment-backed
- do **not** manually patch `.helix/repo-capabilities/*.yml`; re-run setup if discovery needs refreshing

If onboarding surfaced richer repo-specific verification commands or environment notes, use those findings to refine:
- root or nested repo `AGENTS.md`
- `workspaces/{name}/verification-policy.yml`
- future execution-plan `verification` blocks

Capability files inform @hc-decomposer and @hc-reviewer, but they do not replace execution-plan commands. Do NOT hardcode commands — discover them from actual scripts, CI config (`*.yml` in `.github/workflows/`), Makefile, or package.json scripts.

#### 5c. Review Reusable Pattern Candidates

Aggregate the reusable-pattern tables from all onboard outputs. Deduplicate by pattern name or normalized intent. Do not create or project meta-repo skills directly from onboarding evidence alone.

If similar candidates appear in 2 or more repos, or if `.helix/skills/candidates/` already contains matching distill evidence, suggest `/hc-review-reusable-patterns` as the optional maintainer follow-on. That thin prompt may route into `/hc-skill-synth workspace` when the evidence is strong enough for held-out replay and recommendation.

`/hc-skill-synth` is the review gate that validates held-out replay, checks overlap with existing `hc-*` / `hr-*` skills, and recommends one of:
- `PROJECT EXISTING`
- `CREATE NEW`
- `ADD TO EXISTING`
- `NOT WORTH IT`

If the user chooses that follow-on immediately, run `/hc-skill-synth workspace`, present the synth report, and stop for human approval before any projection or meta-root skill creation.

Only after human approval of the synth report should maintainers project an indexed candidate (`helix/scripts/promote-skill.ps1`) or create/update a meta-root skill (`hc-maker`).

#### 5d. Create Workspace Platform AGENTS.md

Create or update `workspaces/{name}/AGENTS.md` as a platform-level architecture document. Include:
- All repos in the workspace, their roles, and primary responsibilities
- End-to-end data flow diagram (mermaid) showing how repos connect
- Shared patterns and conventions common across repos
- Cross-repo glossary terms
- Read-order recommendation for agents working across this workspace

Add this retrieval note at the top:

```
> Agents working in this workspace should read this file before reading individual repo AGENTS.md files.
> It provides platform-level context that individual repo docs do not repeat.
```

#### 5e. Repair Code-Review-Graph

CRG is part of baseline setup. Use this step only to repair or refresh graph state after setup.

If MCP config or runtime is broken, normalize the MCP entry and ensure a usable runtime:

```powershell
./helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode mcp -Bootstrap
```

If graph content is stale or missing after repair, run `/hc-build-graph full`.

## Output

- Updated `.helix/active-workspace.yml`
- Generated `{name}.code-workspace` at the meta-repo root
- Removed Helix-generated legacy `.github/instructions/*.instructions.md` summaries, if present
- Refreshed `.helix/repo-state/*.yml` for the workspace repos (via script, not manual edits)
- Refreshed `.helix/repo-capabilities/*.yml` capability hints for the workspace repos
- Refreshed `.helix/skills/index.yml` for core, projected, and repo-local candidate skills
- Built CRG graphs for present workspace repos when `code_review_graph.mode: mcp`
- A setup report that separates baseline attach and CRG results from optional onboarding work

## Error Handling

```markdown
# Workspace Sync: {name}

| Repo | Path | Present | Readiness | Branch | Next Step |
|------|------|---------|-----------|--------|-----------|
| service-a | workspaces/order-history/repos/service-a | yes | ready | main | none |
| service-b | workspaces/order-history/repos/service-b | cloned | partial | main | onboard |

Generated: {name}.code-workspace, .helix/repo-state/*.yml, .helix/repo-capabilities/*.yml, .helix/skills/index.yml
Updated: .helix/active-workspace.yml
Optional: .claude/settings.local.json when Claude Desktop integration is explicitly requested
```

- Helix not installed → stop and point to `init.ps1` from the Helix source repo
- `helix-repos.yml` (or legacy `repos.yml`) missing or still using placeholder values → stop and ask the user to repair the registry
- `workspace.yml` missing and repo ids supplied → run setup with `-ReposCsv`
- `workspace.yml` missing and repo ids not supplied → stop and point to the installed root `README.md` Start Here section
- `workspace-setup.ps1` fails → surface the script output and do not continue to onboarding
- Onboard fails → report error and leave repo-state at `partial` or `needs-onboarding`
- CRG MCP setup or graph build fails while `mode: mcp` → setup is incomplete; repair CRG or explicitly set `mode: off` as emergency fallback

## Prerequisites

- Helix bootstrap already completed via `init-meta-repo.ps1` from the Helix source checkout or the equivalent installer flow
- `helix-repos.yml` has been updated with the real repo registry (`repos.yml` is accepted only as a legacy alias)
- `workspaces/{name}/workspace.yml` has been created, or explicit repo ids were supplied so `-ReposCsv` can seed it
- CRG MCP bootstrap completed during init, or the user explicitly set emergency `mode: off`
- `git` available
- Prefer `helix/scripts/workspace-setup.ps1` for the target meta-repo model; the old Bash helper is legacy
