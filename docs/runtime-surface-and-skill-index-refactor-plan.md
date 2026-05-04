# Runtime Surface And Skill Index Refactor Plan

Date: 2026-05-01

This plan captures the next Helix cleanup pass for skill routing, instruction surfaces, runtime ownership boundaries, and duplicated agent/skill/prompt contracts.

It is intentionally a plan only. Do not treat this file as an implemented runtime contract until the implementation steps and regression tests land.

## Goals

- Keep the meta repo as the orchestration root.
- Make `.helix/skills/index.yml` an honest skill inventory and routing registry.
- Preserve `AGENTS.md` as the default Helix-managed instruction surface.
- Reduce duplicated instructions across scripts, skills, agents, prompts, and docs.
- Clarify what resume can do from durable artifacts versus optional distilled memory.
- Avoid moving authored state into SQLite or another database unless there is a measured read/query bottleneck.

## Non-Goals

- Do not remove the skill router.
- Do not stop indexing core `hc-*` skills.
- Do not make nested repo-local skills appear host-invokable when the host does not expose them.
- Do not generate `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `CLAUDE.md`, or `GEMINI.md`.
- Do not move workspace artifacts, task boards, decisions, execution plans, or docs into SQLite.

## Design Decisions

### Skill Index

Keep indexing all known skill surfaces:

- meta-root `.github/skills/hc-*`
- meta-root `.github/skills/hr-*`
- workspace repo-local `.github/skills/*`
- later, optionally, personal `~/.copilot/skills/*` as observed external inventory

The index should distinguish inventory from routing fallback. Core and projected skills are already host-visible from the meta root, so the router should not pretend it must load them manually. Repo-local candidates are not guaranteed to be invokable from a meta-root session, so the router may point agents to read their source or recommend projection.

Target metadata:

```yaml
access:
  host_visible: true
  source: meta-root-skill
routing:
  use_mode: invoke
```

Allowed `access.source` values:

- `meta-root-skill`
- `personal-skill`
- `repo-local-nested`
- `generated-candidate`

Allowed `routing.use_mode` values:

- `invoke` - host-visible skill; invoke or reference it normally
- `read-source` - not host-visible; read the source file before acting
- `ignore` - known but should not be selected by normal routing

### Runtime Surface Ownership

Use this ownership split when refactoring:

| Surface | Owns | Must Not Own |
|---|---|---|
| Script | Deterministic state mutation, generation, validation | Long explanatory workflow prose |
| Skill | Reusable operational procedure or playbook | Role identity, orchestration routing, schema rationale |
| Agent | Role, gates, dispatch rules, handoffs | Full procedure text already owned by a skill or script |
| Prompt | Thin host-specific entrypoint | Full workflow or schema duplication |
| Doc | Rationale, schema, examples, migration notes | Runtime state mutation |
| `AGENTS.md` | Durable navigation and non-obvious operating rules | Feature requirements, copied README content, broad narrative |

### Instruction Surfaces

GitHub Copilot can read several instruction surfaces, including `AGENTS.md`, `.github/instructions/**/*.instructions.md`, `.github/copilot-instructions.md`, home instructions, and custom instruction directories.

Helix should remain conservative:

- Helix-managed persistent instructions live in `AGENTS.md`.
- Helix does not generate `.github/copilot-instructions.md`.
- Helix does not generate `.github/instructions/**/*.instructions.md`.
- Helix does not generate `CLAUDE.md` or `GEMINI.md`.
- User-authored instruction files are allowed, but `doctor.ps1` should warn when they may duplicate Helix-managed guidance.

## Implementation Steps

### 1. Add Runtime Surface Contract

Create or update a short reference doc, probably:

```text
helix/docs/runtime-surface-contract.md
```

Content:

- surface ownership table from this plan
- examples of good and bad placement
- rule that implementation details should live in one primary surface and be linked elsewhere
- rule that prompts are host entrypoints, not canonical contracts

Update discovery docs to link it:

- `helix/README.md`
- `helix/docs/AGENTS.md`
- `helix/AGENTS.md`

Acceptance:

- A new contributor can tell where to put a script behavior, skill procedure, agent gate, prompt wrapper, or schema doc.
- No runtime behavior changes in this step.

### 2. Normalize Skill Index Metadata

Update:

- `helix/scripts/Helix.Tools.psm1`
- `helix/docs/meta-repo-skills-management.md`
- `helix/docs/helix-instance-schemas.md`
- `helix/.github/skills/hc-skill-router/SKILL.md`
- `helix/scripts/resolve-skill.ps1`

Implementation:

- Keep existing `skills[]` entries.
- Add `access.host_visible`.
- Add `access.source`.
- Add `routing.use_mode`.
- Mark core `hc-*` as `host_visible: true`, `source: meta-root-skill`, `use_mode: invoke`.
- Mark projected `hr-*` as `host_visible: true`, `source: meta-root-skill`, `use_mode: invoke`.
- Mark repo-local candidates as `host_visible: false`, `source: repo-local-nested`, `use_mode: read-source`.
- Preserve backward compatibility for older index files without `access` or `routing`.

Acceptance:

- Existing resolver behavior still works for old indexes.
- New indexes explain whether a selected skill should be invoked or read as source.
- The router does not instruct agents to manually load host-visible core skills unless there is a specific reason.

Regression tests:

- Core skill indexed as host-visible invoke.
- Projected skill indexed as host-visible invoke.
- Repo-local candidate indexed as not host-visible read-source.
- Resolver output includes `routing.use_mode`.
- Resolver still prefers projected over candidate when both match.
- Resolver still returns `needs_disambiguation` for equal candidates.

### 3. Add Instruction Surface Diagnostics

Update:

- `helix/docs/agents-md-authoring.md`
- `helix/scripts/doctor.ps1`
- possibly `helix/docs/copilot-cli-hooks-and-env.md`

Implementation:

- Document that Helix uses `AGENTS.md` as its managed instruction surface even though Copilot can read additional instruction files.
- Add `doctor.ps1` warnings for:
  - `.github/copilot-instructions.md`
  - `.github/instructions/**/*.instructions.md`
  - root `CLAUDE.md`
  - root `GEMINI.md`
  - configured custom instruction directories, if discoverable from environment or config
- Warnings should not fail validation.
- Do not delete user-authored files.
- Keep existing cleanup for Helix-generated legacy `.instructions.md` summaries only.

Acceptance:

- `doctor.ps1` warns about potential duplicated instruction sources.
- User-authored instruction files remain untouched.
- Generated `.instructions.md` summaries do not reappear.

Regression tests:

- `doctor.ps1` warns when `.github/copilot-instructions.md` exists.
- `doctor.ps1` warns when `.github/instructions/foo.instructions.md` exists.
- `setup-workspace.ps1` removes only Helix-generated legacy instruction summaries with the marker.
- `setup-workspace.ps1` preserves user-authored instruction files.

### 4. De-Duplicate Setup Contracts

Primary duplicated surfaces:

- `helix/.github/agents/hc-setup.agent.md`
- `helix/.github/skills/hc-workspace-sync/SKILL.md`

Target ownership:

- `setup-workspace.ps1` mutates workspace state.
- `hc-workspace-sync` owns the setup procedure and operator playbook.
- `hc-setup.agent.md` owns setup-agent role, preconditions, when to invoke the skill, CRG hard gates, and handoff rules.

Implementation:

- Shrink `hc-setup.agent.md` by replacing repeated procedure blocks with links to `hc-workspace-sync`.
- Keep hard safety rules in the agent:
  - do not modify product code
  - do not rewrite registry/workspace manifests unless requested
  - do not bypass scripts
  - do not continue after baseline setup failure
  - do not silently fall back when CRG `mcp` mode fails
- Keep detailed generated outputs and follow-on setup flow in the skill.

Acceptance:

- Setup flow has one procedural source.
- The setup agent remains capable of enforcing gates and routing.
- No behavior change to scripts.

Regression tests:

- Existing workspace setup tests pass.
- Add a docs/source test that `hc-setup.agent.md` links to `hc-workspace-sync` and does not carry a full duplicate procedure section.

### 5. De-Duplicate Distillation Contracts

Primary duplicated surfaces:

- `helix/docs/distillation-architecture.md`
- `helix/.github/agents/hc-distiller.agent.md`
- `helix/.github/prompts/hc-distill.prompt.md`

Target ownership:

- `distillation-architecture.md` owns persistence layout, schemas, gates, graveyard behavior, and trigger rationale.
- `hc-distiller.agent.md` owns role, decision rules, and high-level workflow.
- `hc-distill.prompt.md` is a thin VS Code prompt wrapper.

Implementation:

- Remove schema duplication from `hc-distill.prompt.md`; link to the doc.
- Reduce `hc-distiller.agent.md` examples to compact output skeletons only.
- Keep the graveyard and append-only candidate rules explicit enough for the agent to act correctly.
- Keep `distill-trigger.js` as reminder-only, not automatic LLM invocation.

Acceptance:

- Schema changes happen in one doc.
- Prompt remains below its current one-screen intent.
- Distiller still has enough rules to avoid auto-promotion and avoid duplicate candidates.

Regression tests:

- Existing distillation trigger tests pass.
- Add a docs/source test that prompt file references `distillation-architecture.md`.

### 6. Clarify Resume Capability

Current issue:

`hc-resume` reads task boards, decisions, memory episodes, and git log. Memory episodes exist only after distillation, so resume must not imply memory is always available.

Target resume levels:

- L0: active workspace and task-board resume
- L1: execution-plan and decisions resume
- L2: trace/session-index aware resume
- L3: distilled memory resume

Implementation plan:

- Update `hc-resume.agent.md` to read in this order:
  1. `.helix/active-workspace.yml`
  2. `workspaces/{id}/workspace.yml`
  3. relevant task board and execution plan
  4. decisions log
  5. `.helix/session-index.jsonl` and latest trace for the workspace, if present
  6. `.helix/memory/index.md`, episodes, and learnings, if present
  7. recent git log in workspace repos
- Clearly mark distilled memory as optional.
- Later, consider adding a deterministic resume snapshot:

```text
workspaces/{id}/resume.yml
```

Possible fields:

```yaml
schema_version: 1
workspace: <id>
updated_at: <iso>
phase:
  current: implementation
  last_completed: task-breakdown
current_task: TASK-003
last_completed_task: TASK-002
blocked_tasks: []
next_action: "Run TASK-003 red test"
artifact_paths:
  execution_plan: execution-plans/<feature>.yaml
  task_board: task-boards/<feature>.md
latest_sessions:
  - <copilot-session-id>
verification_debt: []
```

Acceptance:

- Resume works without `.helix/memory/episodes`.
- Resume gets richer when traces or distilled memory exist.
- No claim that `hc-helix resume` can reconstruct state from raw conversation alone.

Regression tests:

- Add a source/docs test that `hc-resume.agent.md` treats memory as optional.
- If `resume.yml` is implemented later, add parser and schema tests.

### 7. Bloat Audit Sweep

Use line counts as triage, not as an automatic failure.

High-priority surfaces:

- `hc-helix.agent.md`
- `hc-architect.agent.md`
- `hc-setup.agent.md`
- `hc-onboard/SKILL.md`
- `hc-workspace-sync/SKILL.md`
- `hc-playwright-cli/SKILL.md`

Audit questions:

- Does this file own the contract it is describing?
- Is the same workflow repeated in a script, skill, prompt, and doc?
- Can this section become a link to the canonical owner?
- Is this durable instruction, or a phase-specific artifact?
- Is this host-specific wrapper text, or cross-host behavior?

Do not shrink a long skill blindly. Some skills, especially tool-specific reference skills, may need length. Prioritize repeated policy and repeated workflow text.

Acceptance:

- Each reviewed file has one of:
  - no change needed
  - shortened to link to the owner surface
  - split into a doc plus a compact runtime surface
  - explicitly exempted with rationale

### 8. Validation

Run:

```powershell
$tests = Get-ChildItem .\helix\evals\regression\*.test.js | ForEach-Object { $_.FullName }
node --test $tests
```

Also run parser checks for edited PowerShell scripts when applicable:

```powershell
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "helix/scripts/Helix.Tools.psm1",
  [ref]$null,
  [ref]$null
)
```

Acceptance:

- Regression suite passes.
- No generated runtime surface changes unless explicitly intended.
- `git diff` shows docs/procedure cleanup plus targeted script/test changes only.

## Suggested Agent Prompt

Use this prompt for an implementation agent:

```text
Implement helix/docs/runtime-surface-and-skill-index-refactor-plan.md.

Work in small commits or small reviewable patches. Start with steps 1-3 only unless asked to continue. Do not rename core files. Do not remove the skill router. Preserve backward compatibility for existing .helix/skills/index.yml files. Run the Helix regression suite after code changes.

When reducing duplicated text, keep behavior in the canonical owner surface and replace duplicates with links plus the minimum local gate/routing rules needed by that surface.
```

