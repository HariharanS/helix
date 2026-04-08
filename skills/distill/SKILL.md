---
name: distill
description: Extracts learnings from the current or past session — updates episodic memory, long-term learnings, and identifies candidate skills
argument-hint: Optional feature name or "current session"
user-invocable: true
disable-model-invocation: true
---

# Distill Skill

Extracts and persists learnings from development sessions into the Helix memory system.

## What to Distill

1. **Task board state** — read `task-boards/{feature}.md` for progress
2. **Decisions made** — read `decisions/{feature}.md`
3. **Git log** — recent commits related to the feature
4. **Session conversation** — key discussions, pushbacks, corrections

## Outputs

### Episodic Memory (always)

Write to `memory/episodes/YYYY-MM-DD-{feature-slug}.md`:
- What was done (bullet summary)
- Key decisions and rationale
- Blockers and resolutions
- What worked / what didn't

### Long-Term Learnings (if applicable)

Add or update `memory/learnings/{topic}.md` when:
- Something surprising was discovered
- A non-obvious pattern proved effective
- A common mistake was identified
- An approach failed in a specific context

### Skill Candidates (if applicable)

Flag repeating patterns that could be automated as skills.

### Memory Index

Update `memory/index.md` with any new entries.

## Guidelines

- Distill is about LEARNING, not REPORTING
- Focus on the WHY — the code shows WHAT happened
- Keep episodes scannable (under 30 lines)
- Don't duplicate what's in decisions.md — reference it
- Update existing learnings rather than creating duplicates
- Be honest about failures — they're the most valuable learnings
