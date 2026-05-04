# Skill Projection And Simplification Plan

Date: 2026-05-04
Status: Plan only. Not implemented.
Supersedes (in part): `helix/docs/runtime-surface-and-skill-index-refactor-plan.md` Steps 2 and 6 are reframed below. Steps 1, 3, 4, 5, 7, 8 of that plan still apply and are absorbed here.

This plan replaces Helix's current "skill router decides which skill to load" runtime mechanism with a deterministic "all workspace skills are projected to the meta root" data-layer mechanism. The router skill is removed as a runtime dispatcher; its intent-to-skill knowledge moves to durable navigation.

The plan is intentionally conservative: no Copilot CLI extensions yet (covered by `helix/docs/extensions-runtime-future-plan.md`), no SQLite, no host-specific instruction surfaces.

## Goals

- Make every workspace skill host-visible from the meta root through projection.
- Drop the skill router skill as a runtime dispatch mechanism; preserve its selection guidance as durable navigation.
- Apply the surface-ownership cleanup that is still relevant from the prior refactor plan (contract doc, doctor warnings, setup de-dup, distillation de-dup).
- Pull `resume.yml` into scope rather than deferring it.
- Keep PowerShell as the deterministic execution layer; do not add a new runtime surface.

## Non-Goals

- Do not migrate to Copilot CLI extensions (separate plan).
- Do not move authored state into SQLite or any database.
- Do not generate `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md`, `CLAUDE.md`, or `GEMINI.md`.
- Do not delete user-authored instruction files. `doctor.ps1` warns only.
- Do not change agent role files beyond minimum link/de-dup edits.

## Design Decisions

### Projection Model

- Every skill declared in a workspace repo under `.github/skills/<name>/SKILL.md` is projected as a read-only mirror into the meta-root `.github/skills/`.
- Projection scope is the **active workspace only**. Switching workspaces removes the previous workspace's projections and projects the new workspace's skills.
- Source of truth is the source repo. Meta-root projections carry provenance frontmatter and are read-only on disk.
- `hc-*` skills are Helix core (live in meta-root, not projected).
- `hr-*` skills are Helix-reusable (already projected today by `hc-workspace-sync`); generalize the same mechanism to all workspace skills.

### Naming And Collisions

- Projected skill folder name: `{repo-short}-{skill-name}` where `repo-short` comes from the repo registry's short name (e.g. `mobile-checkout` projects `code-review` as `mobile-checkout-code-review`).
- The original repo-local skill keeps its un-prefixed name; only the projection is renamed.
- If two repos in the active workspace would project to the same final folder name (collision after prefixing), projection MUST fail hard with a clear error pointing at both source paths. Do not silently overwrite.

### Skills That Should Not Be Projected

Some skills are tied to a specific repo's filesystem layout or local tooling (e.g. "run `npm test` in this directory"). Those skills must declare `projection: never` in their `SKILL.md` frontmatter and are skipped by the projector.

### Index As Projection Ledger, Not Routing Registry

- `.helix/skills/index.yml` survives as the manifest of what was projected and from where, used by `hc-workspace-sync` to clean up correctly on workspace switch.
- It no longer drives runtime routing decisions. Drop `routing.use_mode`.
- Keep `access.source` as informational metadata only.

### Skill Router Skill Removed As Runtime Dispatcher

- `helix/.github/skills/hc-skill-router/SKILL.md` is deleted (or shrunk to a one-line pointer at the doc).
- Intent-to-skill selection guidance moves to `helix/AGENTS.md` (or a linked doc).
- `helix/scripts/resolve-skill.ps1` is kept as a developer/CI utility for verifying projection correctness, not as an agent-invoked router.

### CWD Assumption

- Helix sessions are expected to run with current working directory at the meta root. Copilot CLI discovers `.github/skills/` from CWD; projection only pays off if sessions start at the meta root.
- `doctor.ps1` warns when invoked from a non-meta-root CWD.

### Resume.yml Pulled Into Scope

The prior refactor plan deferred `workspaces/{id}/resume.yml`. It is in scope here because the user's primary unanswered concern was "does `hc-helix resume` actually work?". A deterministic snapshot file is the answer; `hc-resume.agent.md` reads it first, then falls back to L0–L3 sources.

## Implementation Steps

Steps may be implemented in order. Steps 1, 4, 5, 8 are independent and can run in parallel patches. Steps 2, 3, 6 are tightly coupled and should land together. Step 9 (resume.yml) depends on no other step. Step 10 (validation) runs last.

### Step 1: Runtime Surface Contract Doc

Create `helix/docs/runtime-surface-contract.md` containing:

- Surface ownership table (script / skill / agent / prompt / doc / `AGENTS.md`) from the prior refactor plan.
- Examples of good vs. bad placement for each surface.
- Rule: implementation details live in one primary surface and are linked elsewhere.
- Rule: prompts are host-specific entrypoints, not canonical contracts.

Link from:

- `helix/README.md`
- `helix/AGENTS.md`
- `helix/docs/AGENTS.md`

Acceptance:

- A new contributor can read the contract and decide where new behavior belongs.
- No runtime behavior changes.

### Step 2: Generalize Projection Mechanism

Files to update:

- `helix/scripts/Helix.Tools.psm1`
- `helix/scripts/setup-workspace.ps1`
- `helix/scripts/workspace-setup.ps1`
- `helix/.github/skills/hc-workspace-sync/SKILL.md`
- `helix/docs/meta-repo-skills-management.md`

Implementation:

- In `Helix.Tools.psm1`, add an exported function:
  ```
  Project-WorkspaceSkill -SourceRepoRoot <path> -RepoShortName <string> -SkillRelPath <path> -MetaRoot <path>
  ```
  Behavior:
  1. Read source `SKILL.md` frontmatter.
  2. If `projection: never`, skip and return `$null`.
  3. Compute target folder: `{MetaRoot}/.github/skills/{RepoShortName}-{SkillName}/`.
  4. If target already exists with a different `projection.from_path`, throw a collision error.
  5. Copy entire skill folder contents (SKILL.md plus any sibling files) to target.
  6. Inject/overwrite frontmatter on target `SKILL.md`:
     ```yaml
     projection:
       from_repo: <RepoShortName>
       from_path: <SkillRelPath>
       projected_at: <ISO 8601 UTC>
       checksum: <sha256 of source SKILL.md plus any sibling assets>
     ```
  7. Set the projected `SKILL.md` (and all copied files) to read-only on disk (Windows `ReadOnly` attribute, POSIX `0o444` — handle both code paths).
  8. Return the projection ledger entry (an object the caller will write to `index.yml`).

- Add a sibling exported function:
  ```
  Get-WorkspaceSkillSources -WorkspaceId <string>
  ```
  Returns, for each repo in the active workspace, the list of `.github/skills/*/SKILL.md` paths plus computed `RepoShortName`.

- `setup-workspace.ps1` and `hc-workspace-sync` SKILL.md call these functions in sequence:
  1. Resolve workspace from `.helix/active-workspace.yml`.
  2. For each repo, project skills (skipping `projection: never`).
  3. Update `.helix/skills/index.yml` (see Step 6).

Acceptance:

- Running `setup-workspace.ps1` on a workspace whose repos contain skills produces visible projections under `helix/.github/skills/{repo-short}-*/`.
- Each projected `SKILL.md` carries provenance frontmatter.
- Files are read-only.
- Skills tagged `projection: never` are not projected.
- Collisions throw a clear error naming both source paths.

Regression tests (add to `helix/evals/regression/`):

- `projection-basic.test.js`: synthetic workspace with two repos each having one skill; assert both projected with correct prefixes.
- `projection-skip.test.js`: skill with `projection: never`; assert not projected.
- `projection-collision.test.js`: two repos with skills that would project to the same target; assert hard error.
- `projection-readonly.test.js`: assert projected file is read-only.
- `projection-frontmatter.test.js`: assert provenance fields present and valid.

### Step 3: Workspace Switch Cleanup

Files to update:

- `helix/scripts/Helix.Tools.psm1`
- `helix/scripts/setup-workspace.ps1`
- `helix/.github/skills/hc-workspace-sync/SKILL.md`

Implementation:

- Add exported function `Remove-WorkspaceProjections -WorkspaceId <string>` that:
  1. Reads `.helix/skills/index.yml`.
  2. For each entry whose `projection.from_repo` belongs to the previous workspace, removes the read-only attribute and deletes the folder under `helix/.github/skills/`.
  3. Removes those entries from the index.
- Update `Set-ActiveWorkspace` (or equivalent in `setup-workspace.ps1`) to:
  1. Call `Remove-WorkspaceProjections` for the previous active workspace.
  2. Update `.helix/active-workspace.yml`.
  3. Project skills for the new active workspace.
- Never delete `hc-*` (core) or `hr-*` (Helix-reusable) skills under any circumstance.

Acceptance:

- Switching from workspace A (with repos X, Y) to workspace B (with repos Z) results in all projections from X and Y removed, projections from Z added, and `hc-*`/`hr-*` untouched.

Regression tests:

- `workspace-switch-cleanup.test.js`: synthetic two-workspace scenario; switch and assert projection set matches new workspace.
- `workspace-switch-preserves-core.test.js`: assert `hc-*` and `hr-*` skills are untouched across switches.

### Step 4: Drop Router As Dispatch

Files to change:

- Delete `helix/.github/skills/hc-skill-router/SKILL.md` (preferred), OR shrink it to one paragraph that links to the new selection doc.
- Create or extend a section in `helix/AGENTS.md` titled "Choosing a skill" containing the intent-to-skill mapping rules previously in the router skill.
- Optional: create `helix/docs/skill-selection.md` if the AGENTS.md addition would be too long (target: keep AGENTS.md under its current length).
- Search and update every reference to `hc-skill-router` in:
  - `helix/.github/agents/*.agent.md`
  - `helix/.github/prompts/*.prompt.md`
  - `helix/docs/*.md`
  - `helix/.github/skills/*/SKILL.md`
- Replace references with a link to the new selection guidance.

Implementation note: do NOT delete `helix/scripts/resolve-skill.ps1`. Keep it as a developer/CI utility (for example, used by Step 6 doctor checks to verify projections).

Acceptance:

- No agent file references `hc-skill-router` as a runtime dispatcher.
- Skill selection guidance exists in exactly one canonical surface.
- `resolve-skill.ps1` still parses and runs; its tests still pass.

Regression tests:

- `router-removal-references.test.js`: grep `helix/.github/agents/` and `helix/.github/prompts/` for `hc-skill-router`; assert zero matches except in archived/changelog files.
- `skill-selection-doc-exists.test.js`: assert `helix/AGENTS.md` contains a "Choosing a skill" section OR `helix/docs/skill-selection.md` exists and is linked from AGENTS.md.

### Step 5: De-Duplicate Setup Contracts

Carried over from the prior refactor plan (Step 4 there).

Files:

- `helix/.github/agents/hc-setup.agent.md`
- `helix/.github/skills/hc-workspace-sync/SKILL.md`

Ownership target:

- `setup-workspace.ps1` mutates state.
- `hc-workspace-sync` owns the procedure and operator playbook.
- `hc-setup.agent.md` owns the role: gates, preconditions, when to invoke the skill, CRG hard gates, handoff rules.

Pre-implementation prep (do this in the patch description, not in code):

- List the section headings currently duplicated between `hc-setup.agent.md` and `hc-workspace-sync/SKILL.md`.
- For each duplicated section, decide: keep in agent (gate/role), keep in skill (procedure), or split.

Implementation:

- Replace duplicated procedural blocks in `hc-setup.agent.md` with links to `hc-workspace-sync`.
- Keep the following hard rules in the agent file:
  - do not modify product code
  - do not rewrite registry/workspace manifests unless requested
  - do not bypass scripts
  - do not continue after baseline setup failure
  - do not silently fall back when CRG `mcp` mode fails

Acceptance:

- One procedural source for setup.
- Agent retains gate enforcement.
- No script behavior change.

Regression tests:

- `setup-no-procedure-duplication.test.js`: assert `hc-setup.agent.md` does not contain the canonical procedural step list (use a marker token in `hc-workspace-sync/SKILL.md` and assert it is not duplicated in the agent).
- Existing setup tests pass unchanged.

### Step 6: Index As Projection Ledger

Files to update:

- `helix/scripts/Helix.Tools.psm1` (index read/write functions)
- `helix/docs/helix-instance-schemas.md`
- `helix/docs/meta-repo-skills-management.md`
- `helix/scripts/resolve-skill.ps1`

Schema (target):

```yaml
schema_version: 2
skills:
  - name: hc-architect
    path: .github/skills/hc-architect
    access:
      source: meta-root-skill
    # no projection block for core
  - name: mobile-checkout-code-review
    path: .github/skills/mobile-checkout-code-review
    access:
      source: projected
    projection:
      from_repo: mobile-checkout
      from_path: .github/skills/code-review
      projected_at: 2026-05-04T10:30:00Z
      checksum: sha256:abc...
```

Removed fields:

- `routing.use_mode` — gone, every projected skill is `invoke`.
- `access.host_visible` — gone, projection guarantees visibility.

Backward compatibility:

- Reader tolerates `schema_version: 1` indexes (older shape with `routing` and `access.host_visible`); upgrade-on-read converts to v2 in memory.
- Writer always emits v2.
- `setup-workspace.ps1` upgrades the file on disk on first run.

Acceptance:

- New indexes match v2 schema.
- Old v1 indexes still load through a one-time conversion.
- `resolve-skill.ps1` works against both shapes.

Regression tests:

- `index-schema-v2.test.js`: assert new projections produce v2 entries.
- `index-schema-v1-compat.test.js`: load a v1 fixture; assert successful conversion.
- `index-no-routing-field.test.js`: assert v2 index does not emit `routing` field.

### Step 7: De-Duplicate Distillation Contracts

Carried over from the prior refactor plan (Step 5 there). No changes from that plan.

Files:

- `helix/docs/distillation-architecture.md` — owner of schemas, gates, graveyard, triggers.
- `helix/.github/agents/hc-distiller.agent.md` — role and decision rules.
- `helix/.github/prompts/hc-distill.prompt.md` — thin VS Code prompt wrapper.

Implementation: remove schema duplication from prompt; reduce agent examples to compact skeletons. Keep graveyard and append-only candidate rules explicit. Keep `distill-trigger.js` reminder-only.

Acceptance, regression tests: as in prior plan.

### Step 8: Doctor Diagnostics

Files to update:

- `helix/scripts/doctor.ps1`
- `helix/docs/agents-md-authoring.md`
- `helix/docs/copilot-cli-hooks-and-env.md` (link only)

Add the following warnings (none should fail validation; emit at warn level):

1. **CWD not at meta root.** Detect by comparing `(Get-Location).Path` to the meta-root marker (existence of `.helix/` plus a `meta_root: true` marker in `.helix/active-workspace.yml` or the like).
2. **Hand-edited projection.** For each entry in `.helix/skills/index.yml` with a `projection.checksum`, recompute the checksum of the projected file and warn on mismatch. Suggested message: "Projected skill X has been hand-edited; edits should happen in source repo Y at path Z, then re-run setup-workspace."
3. **Stale projection.** For each projection, recompute the checksum of the **source** file in the source repo. If different from `projection.checksum`, warn that the projection is stale and `setup-workspace` should be re-run.
4. **User-authored instruction surfaces.** Warn when any of the following exist (do NOT delete):
   - `.github/copilot-instructions.md`
   - `.github/instructions/**/*.instructions.md`
   - root `CLAUDE.md`
   - root `GEMINI.md`

Existing cleanup of Helix-generated legacy `.instructions.md` summaries (if any) should keep working — only remove files that carry the Helix-generated marker.

Acceptance:

- `doctor.ps1` warns for each diagnostic without failing.
- User-authored instruction files remain on disk.
- Helix-generated legacy summaries continue to be cleaned up.

Regression tests:

- `doctor-cwd-warning.test.js`: invoke doctor from a non-meta-root path; assert warning emitted.
- `doctor-hand-edit-warning.test.js`: write to a projected file (after relaxing readonly in the test); assert warning.
- `doctor-stale-projection-warning.test.js`: modify source skill but skip re-projection; assert warning.
- `doctor-user-instructions-warning.test.js`: place `.github/copilot-instructions.md`; assert warning, assert file untouched.

### Step 9: Resume.yml And Resume Capability

Files to update:

- `helix/.github/agents/hc-resume.agent.md`
- `helix/scripts/Helix.Tools.psm1`
- `helix/scripts/setup-workspace.ps1` (initial creation on workspace setup)
- Any task-board / decisions logging script (locate via grep on `decisions.md` and `task-board`)
- `helix/docs/helix-instance-schemas.md` (document the schema)

Implementation:

- Define `workspaces/{id}/resume.yml` schema:
  ```yaml
  schema_version: 1
  workspace: <id>
  updated_at: <ISO 8601 UTC>
  phase:
    current: <discovery|design|implementation|verification|review>
    last_completed: <phase>
  current_task: <task_id|null>
  last_completed_task: <task_id|null>
  blocked_tasks: [<task_id>, ...]
  next_action: <short imperative string>
  artifact_paths:
    execution_plan: <path|null>
    task_board: <path|null>
    decisions_log: <path|null>
  latest_sessions:
    - <copilot-session-id>
  verification_debt: [<short string>, ...]
  ```
- Add exported function `Update-ResumeSnapshot -WorkspaceId <string> -Patch <hashtable>` that merges `Patch` into the existing `resume.yml`, bumps `updated_at`, and writes back.
- Trigger updates from:
  - Workspace setup (initial create with phase=`discovery`).
  - Task transitions (called by whatever script/skill currently writes the task board).
  - Decision recording.
  - End of session (best-effort; if no hook is available, an explicit prompt-driven update is acceptable).
- Update `hc-resume.agent.md` to read in this order:
  1. `.helix/active-workspace.yml`
  2. `workspaces/{id}/workspace.yml`
  3. `workspaces/{id}/resume.yml` ← primary new source
  4. relevant task board and execution plan
  5. decisions log
  6. `.helix/session-index.jsonl` and latest trace, if present
  7. `.helix/memory/index.md`, episodes, learnings (if present, mark optional)
  8. recent git log
- Mark distilled memory as **optional** in the agent file. Resume must succeed when `.helix/memory/episodes/` is empty or absent.

Acceptance:

- A workspace with no memory at all produces a useful resume from `resume.yml` plus task board.
- Resume gets richer when traces or distilled memory exist.
- The agent file no longer claims memory is required.

Regression tests:

- `resume-yml-create.test.js`: setup-workspace creates a `resume.yml` with `phase.current` set.
- `resume-yml-merge.test.js`: `Update-ResumeSnapshot` patches a single field without overwriting others.
- `resume-without-memory.test.js`: synthetic workspace with no `.helix/memory/`; assert resume agent reads `resume.yml` and produces a valid summary.
- `resume-agent-memory-optional.test.js`: source check that `hc-resume.agent.md` contains the word "optional" near the memory references.

### Step 10: Validation

Run after each step's patch and once at the end:

```powershell
$tests = Get-ChildItem .\helix\evals\regression\*.test.js | ForEach-Object { $_.FullName }
node --test $tests
```

Parser checks for edited PowerShell:

```powershell
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "helix/scripts/Helix.Tools.psm1",
  [ref]$null,
  [ref]$null
)
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "helix/scripts/setup-workspace.ps1",
  [ref]$null,
  [ref]$null
)
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "helix/scripts/doctor.ps1",
  [ref]$null,
  [ref]$null
)
```

Acceptance:

- Full regression suite passes.
- No generated runtime surface changes that were not explicitly intended.
- `git diff` shows: doc additions, projection mechanism extension, index schema bump, doctor warnings, resume.yml plumbing, router removal, setup/distillation de-dup. Nothing else.

## Rollback Plan

If a step regresses behavior:

- Step 2/3/6 are coupled. Roll back as a unit.
- Step 4 (router removal) — restore `hc-skill-router/SKILL.md` from git.
- Step 9 (resume.yml) — `Update-ResumeSnapshot` is additive; roll back by deleting the file and reverting agent file.
- Step 8 (doctor warnings) — warnings are non-failing; safe to leave or roll back individually.

## Suggested Agent Prompt

Use this prompt for an implementing agent:

```
Implement helix/docs/skill-projection-and-simplification-plan.md.

Constraints:
- Work in small reviewable patches, one step at a time.
- Steps 2, 3, 6 must land together (they share the projection ledger).
- Do not migrate to Copilot CLI extensions in this plan.
- Do not touch SQLite or any database.
- Preserve backward compatibility for schema_version 1 indexes.
- Do not remove or modify hc-* and hr-* core skills.
- Do not delete user-authored instruction files; only warn.
- After each step's patch, run the regression suite under helix/evals/regression/ and the PowerShell parser checks listed in Step 10.
- For the router removal in Step 4: prefer deletion over a stub. Move skill-selection guidance to helix/AGENTS.md.

Start with Step 1 only and stop for review. Continue with Steps 2-3-6 as a single patch when asked.
```
