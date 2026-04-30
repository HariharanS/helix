---
name: hc-skill-synth
managed-by: helix-core
description: Reviews reusable-pattern evidence after onboarding or distill, validates skill-worthiness, and recommends projection, creation, or rejection actions
argument-hint: "Scope to review (e.g. 'workspace', '../service-a', or 'candidate payment-contract-fixtures')"
user-invocable: true
disable-model-invocation: true
---

# Skill Synth

Reviews reusable-pattern evidence after onboarding or distill and decides whether Helix should project an existing candidate, create a new meta-root skill, extend an existing skill, or reject the pattern.

This is a **maintainer** workflow, not part of the default newcomer setup path.

Run it when:

- onboarding or refresh surfaced reusable-pattern evidence worth cross-repo review
- distiller evidence reached the held-out replay gate
- a maintainer wants to review whether repo-local skill candidates should become workspace/meta-root runtime skills

Do NOT make ordinary developers run this as part of basic workspace setup. Setup may suggest it as an optional maintainer follow-on after onboarding succeeds.

## Evidence Order

Review evidence in this order before doing any new scanning:

1. Existing meta-root skills in `.github/skills/hc-*` and `.github/skills/hr-*`
2. `.helix/skills/index.yml` candidate and projection metadata
3. Reusable-pattern tables or equivalent evidence emitted by `hc-onboard`
4. `.helix/skills/candidates/{id}.md` files written by distiller
5. Targeted repo evidence gathered with CRG and minimal supporting file reads

If onboarding evidence was shown inline and not persisted, reconstruct only the missing shortlist entries from indexed repo-local skills plus targeted CRG evidence. Do not restart with blind repo-wide scanning if good evidence already exists.

## Retrieval Contract

- Read `.helix/context-providers.yml` before code discovery.
- If `code_review_graph.mode` is `mcp`, use CRG as the **primary** retrieval engine for code-level evidence, structural repetition checks, symbol lookups, and held-out replay.
- In `mode: mcp`, a missing or empty graph is a hard setup error. Stop and repair CRG; do not silently fall back to broad grep-first scanning.
- Manual reads are still expected for README/docs, manifests, IaC, CI config, and other non-code artifacts that CRG does not model well.
- Manual multi-pass code scanning is allowed only when `code_review_graph.mode` is explicitly `off`.

## Workflow

### 1. Resolve Scope

- Determine whether the operator asked for:
  - a **workspace** review
  - a **single repo** review
  - a **specific candidate** review
- If the scope is `workspace`, read `.helix/active-workspace.yml` and the workspace repo list first.
- Read `.helix/skills/index.yml` and inventory existing `hc-*` / `hr-*` skills before reviewing any candidates.

### 2. Intake Existing Evidence

Collect candidate evidence before deriving new conclusions:

- onboarding reusable-pattern tables, repo-local candidate skills, and generated AGENTS.md guidance
- distiller candidate files under `.helix/skills/candidates/`
- existing matching `hc-*` / `hr-*` skills and indexed repo-local candidates
- targeted CRG evidence for files/symbols named in the candidate evidence

If evidence is thin or conflicting, refresh only the missing facts with targeted CRG queries and the smallest supporting file reads needed to verify them.

### 3. Shortlist And Dedupe

Normalize and group candidates by intent:

- Merge equivalent patterns discovered in multiple repos or phases.
- Keep repo-local patterns separate from likely workspace/meta candidates.
- Remove entries already fully covered by an existing `hc-*` or `hr-*` skill.
- If two candidates share a name but not a shape, keep them separate and note the collision.

### 4. Validate Reusability

For each serious candidate, do NOT stop at frequency. Validate that it can become a stable skill:

1. **Variation analysis**
   - Compare at least 3 occurrences when available
   - Separate fixed boilerplate from true parameters
   - Record where the pattern varies and why
2. **Parameter extraction**
   - Define the smallest set of inputs needed to reproduce the pattern
   - Reject the candidate if too much of the output is bespoke or context-heavy
3. **Held-out replay**
   - Pick at least one occurrence not used to derive the template
   - Use CRG plus targeted file reads to test whether the proposed parameters + workflow could recreate it accurately
   - If replay fails, downgrade or reject the candidate
4. **Existing-skill overlap**
   - Decide whether the candidate should project an indexed repo-local skill, extend an existing meta-root skill, or become a net-new skill

### 5. Recommend The Next Action

Every reviewed candidate must end with exactly one recommendation:

- `PROJECT EXISTING` — an indexed repo-local candidate already exists and is suitable for meta-root projection
- `ADD TO EXISTING` — an existing `hc-*` or `hr-*` skill already covers most of the pattern and should be extended
- `CREATE NEW` — no existing skill fits and the pattern passes the reusability bar
- `NOT WORTH IT` — the pattern is too bespoke, too weakly evidenced, or too expensive to maintain

### 6. Report And Handoff

Produce a candidate report:

```markdown
# Skill Synthesis Report: {repo or workspace}
**Scanned:** {date}
**Mode:** workspace-review | repo-review | candidate-review
**Evidence sources:** onboard | distill | index | crg | manual
**Candidates reviewed:** {N}

## Candidates

### 1. {Pattern Name}
- **Type:** file-level | code-level | workflow-level | config-level
- **Sources:** onboard | distill | both
- **Scope hypothesis:** repo-local | workspace/meta | helix-core
- **Example:** {one concrete example from the codebase}
- **Parameters:** {true variable inputs needed to drive the pattern}
- **Fixed boilerplate:** {what stays constant across occurrences}
- **Variation notes:** {where the pattern diverges across examples}
- **Existing skill overlap:** {none | skill name + gap}
- **Held-out replay:** PASS | PARTIAL | FAIL
- **Recommendation:** PROJECT EXISTING | CREATE NEW | ADD TO EXISTING | NOT WORTH IT
- **Operator next step:** `promote-skill.ps1` | `hc-maker` | extend existing skill | none

## Rejected Patterns
- {Pattern}: {why it's not worth a skill}
```

When the recommendation is:

- `PROJECT EXISTING` → suggest `helix/scripts/promote-skill.ps1 -SkillId <id>`
- `CREATE NEW` → hand off to `hc-maker` with the validated parameters and examples
- `ADD TO EXISTING` → name the existing skill and the missing behavior to fold in
- `NOT WORTH IT` → retain the evidence only; no projection or creation step

## Guidelines

- Stay tech-agnostic. Describe the pattern, not the framework fandom.
- Prefer onboarding/distill evidence over speculative broad scanning.
- Use CRG first for code evidence when `mode: mcp`.
- Only recommend meta-root work for patterns that matter across more than one task, repo, or feature surface.
- A skill should save more time than it costs to maintain
- Prefer fewer, higher-quality skills over many trivial ones
- Check if the pattern is already covered by an existing skill before recommending new work
- Do NOT recommend `CREATE NEW` unless held-out replay passes or is very close with clearly bounded gaps
- Reject candidates whose true parameter list is too large or whose variation is driven by business-specific logic
- Never auto-project or auto-create a skill from this workflow. Human approval is required.
