---
name: skill-audit
description: Generate the quarterly skill audit at .helix/skills/audits/{YYYY-Q#}.md from candidates + graveyard + usage.jsonl
mode: ask
tools: ['read', 'edit']
---

Produce the quarterly audit for `.helix/skills/`. Schema is in `helix/docs/distillation-architecture.md` under `audits/{YYYY-Q#}.md`.

Steps:

1. Resolve quarter. Default: today's quarter as `YYYY-Q#` (Q1=Jan-Mar, Q2=Apr-Jun, Q3=Jul-Sep, Q4=Oct-Dec). If `${input:quarter}` is provided, use it verbatim — must match `^\d{4}-Q[1-4]$`.
2. If `.helix/skills/audits/{quarter}.md` exists, read it and ask the operator whether to overwrite. If they decline, stop.
3. Walk `.helix/skills/candidates/*.md`. For each, parse the frontmatter. Collect every entry where `status: promoted` AND the most recent `## Evidence Log` date falls inside the quarter window. Record `id`, promotion date, `occurrences`, `len(features)`.
4. Walk `.helix/skills/graveyard/*.md`. Collect every entry whose `graveyarded` date falls inside the quarter window. Record `id`, `graveyarded`, `reason`.
5. Read `.helix/skills/usage.jsonl` if present. Filter records whose `ts` falls inside the quarter. Compute per-skill: invocation count, count of non-null `edit_distance`, mean edit_distance. Skip the section entirely if no records have non-null `edit_distance`.
6. Write `.helix/skills/audits/{quarter}.md` with frontmatter (`quarter`, `promoted_count`, `graveyarded_count`) and the three sections (`## Promotions`, `## Graveyards`, `## Edit-distance trend`). Empty sections render as `_None._` — never omit a section heading.
7. End with a one-line summary: counts + path written.

Do NOT promote, demote, or modify any candidate / graveyard / usage file. Audit is read-only over those inputs.

${input:quarter:Optional — quarter to audit in YYYY-Q# form (defaults to current)}
