---
name: skill-graveyard
description: Move a skill candidate into .helix/skills/graveyard/ with operator-supplied reason and re-suggest fingerprint
mode: ask
tools: ['read', 'edit']
---

Graveyard a skill candidate so the distiller stops re-suggesting it. Schema is in `helix/docs/distillation-architecture.md` under `graveyard/{id}.md`.

Steps:

1. Read `${input:id}`. Reject if it does not match `^[a-z0-9]+(-[a-z0-9]+)*$` (kebab-case) — ask the operator to retype.
2. Look for `.helix/skills/candidates/{id}.md`. If absent, ask the operator to confirm they want to graveyard a non-existent candidate (use case: pre-emptively block a pattern). If they decline, stop. If present, parse the frontmatter to capture the human title (from the `# Candidate: ...` heading) and the current `status` value (used as `last_status_before`).
3. If `.helix/skills/graveyard/{id}.md` already exists, show the operator the existing reason and stop — graveyarding is idempotent and overwriting requires manual edit.
4. Ask three questions, one at a time, re-asking on out-of-enum:
   - `reason`: `too-bespoke | covered-elsewhere | low-frequency | replay-fails | operator-rejected`
   - `prose`: free-form explanation of why this pattern is being rejected
   - `fingerprint`: short pattern description used to suppress future near-duplicates (single line, what would you tell a future you to recognize this case)
5. Write `.helix/skills/graveyard/{id}.md` with frontmatter (`id`, `graveyarded: <today YYYY-MM-DD>`, `reason`, `last_status_before: candidate | promoted`), then `# Graveyarded: <title or id-as-title>`, then `## Reason` containing the prose, then `## Don't re-suggest if` with `- Pattern matches: <fingerprint>`.
6. If the candidate file existed, delete `.helix/skills/candidates/{id}.md` after the graveyard file is written. The full evidence log lives in git history.
7. End with a one-line summary: `graveyarded {id} — reason: {reason}`.

Do NOT modify `usage.jsonl` or any audit file.

${input:id:Required — kebab-case id of the candidate to graveyard}
