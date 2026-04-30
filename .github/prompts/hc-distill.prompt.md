---
name: hc-distill
description: Run the distiller against the active workspace; accumulate evidence in .helix/skills/candidates/, respect the graveyard
mode: agent
agent: hc-distiller
tools: ['read', 'edit', 'search/codebase']
---

Distill the active workspace's most recent session(s) into delivery memory, runtime learnings, and promotion candidates. The full architecture (persistence layout, schemas, gates, graveyard rules) is in `helix/docs/distillation-architecture.md` — read it before producing candidates.

Required behaviour:

1. Read `.helix/active-workspace.yml` to identify the workspace. If none is active, ask the operator which to distil and stop until answered.
2. Produce delivery distill (always) — `.helix/memory/episodes/YYYY-MM-DD-{feature-slug}.md` per the existing distiller contract.
3. Produce runtime distill (when applicable) — `.helix/memory/learnings/{topic}.md`.
4. **For each promotion candidate:**
   - Compute a kebab-case `id` from the pattern.
   - Check `.helix/skills/graveyard/{id}.md`. If it exists and the "Don't re-suggest if" fingerprint matches, suppress the candidate and list it under `## Suppressed (graveyarded)` in the session report. Move on.
   - Check `.helix/skills/candidates/{id}.md`. If it exists, **append** a new dated block to its `## Evidence Log` and bump frontmatter (`occurrences`, `features` set union, `last_evidence`). Do NOT rewrite prior entries.
   - If it does not exist, create it with the schema in `distillation-architecture.md`.
5. After updating candidates, evaluate the promotion gate for each: `occurrences ≥ 3 AND len(features) ≥ 2 AND held_out_replay = PASS AND quarterly_promotions < 5`. Set `Status:` accordingly. If `ELIGIBLE`, recommend handing off to `/hc-maker`; do NOT generate the SKILL.md from this prompt.
6. End with a single-screen summary: episode written, learnings touched, candidates updated/created/suppressed, eligible for promotion.

${input:scope:Optional — feature slug to distil instead of the most recent session}
