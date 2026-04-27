---
name: distill
managed-by: helix-core
description: Distills sessions into delivery memory, runtime learnings, and classified promotion candidates — supports optional chronicle enrichment; never depends solely on it
argument-hint: Optional feature name or "current session"
user-invocable: true
disable-model-invocation: true
---

# Distill Skill

Persists session learnings into the Helix memory system across three typed outputs: delivery distill, runtime distill, and promotion distill.

## Optional Chronicle Enrichment

Before distilling, check for `.helix/memory/chronicle/{feature-slug}.md` or `workspaces/{name}/chronicle.md`. If present, use as an enrichment signal — it may surface detail the task board misses. If absent, proceed without it. Chronicle is advisory, never the primary input.

## What to Collect

1. **Task board state** — `workspaces/{workspace}/task-boards/{feature}.md`
2. **Decisions made** — `workspaces/{workspace}/decisions/{feature}.md`
3. **Git log** — recent commits related to the feature (across workspace repos)
4. **Implementer outputs** — task confidence levels, deferred_verification entries
5. **Slice verification state** — any `done-unverified` slices and VERIFY-* follow-up tasks
6. **Chronicle** (if present) — use to enrich; never as sole source

## Outputs

### 1. Delivery Distill (always)

Write to `.helix/memory/episodes/YYYY-MM-DD-{feature-slug}.md`:
- What was done (bullet summary)
- Workspace name and repos touched
- Key decisions and rationale (reference decisions log, don't duplicate)
- Blockers and resolutions
- Verification state: verified slices vs. deferred (list outstanding VERIFY-* tasks)
- What worked / what didn't

### 2. Runtime Distill (if applicable)

Add or update `.helix/memory/learnings/{topic}.md` when:
- Something surprising was discovered
- A non-obvious pattern proved effective
- A common mistake was identified
- An approach failed in a specific context

### 3. Promotion Distill (if applicable)

Flag repeating patterns as promotion candidates. Classify by destination before feeding to `/skill-synth`:

| Destination | Target location | Gate |
|-------------|----------------|------|
| `repo` | `{repo}/.github/skills/` | Repo-specific, unlikely in siblings |
| `workspace/meta` | `{meta-repo}/.github/skills/` | 2+ repos, consistent parameterization, no existing meta skill |
| `helix-core` | Propose to maintainers | Orchestration-level, not product-specific |
| `personal` | User personal skills dir | User-preference workflow |

For each candidate, record: pattern name, destination, evidence (file + symbol), frequency, and recommendation (create / add-to-existing / not-worth-it).

Do NOT create skills from this skill — present candidates for human review, then delegate to `/skill-synth`.

### Memory Index

Update `.helix/memory/index.md` with any new entries.

## Guidelines

- Delivery distill is learning, not reporting — focus on WHY, not WHAT
- Keep episodes scannable (under 35 lines)
- Don't duplicate decisions log — reference it
- Update existing learnings rather than creating duplicates
- Record verification debt state honestly — deferred verifications are delivery facts
- Chronicle enrichment must be grounded by task board + git log evidence
