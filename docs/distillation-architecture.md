# Distillation Architecture

How Helix distils sessions into reusable skills *over time, across features*. Replaces the "one-shot distill per session" pattern with an evidence-accumulating, graveyard-aware pipeline.

## Why this exists

Today the distiller writes per-session episodes + learnings + promotion-candidate reports. Every candidate is evaluated against one feature. That doesn't compound. The plan §6 requirement is: a candidate accumulates evidence across features, and only promotes once N occurrences across M features pass held-out replay.

This doc specifies the persistence layer + trigger architecture that makes compounding possible. **Scaffolding only** — directory shapes, schemas, gates, triggers, agent contract. The actual quality loop (auto-graveyard via edit distance, two-pass synthesis) waits for real usage.

## Persistence layout

```
.helix/skills/
├── candidates/        # Active accumulating evidence
│   └── {id}.md       # One file per pattern; appended to across features
├── graveyard/        # Rejected candidates
│   └── {id}.md       # Distiller checks before re-suggesting
├── audits/           # Quarterly review records
│   └── {YYYY-Q#}.md  # Promotions made this quarter, edit-distance trends
└── usage.jsonl       # Append-only log of skill invocations
```

`.helix/skills/` is per-meta-repo (cross-repo aggregation happens here, not per sub-repo). Directories ship empty; the distiller creates `{id}.md` files lazily.

## Schemas

### `candidates/{id}.md`

```markdown
---
id: <kebab-case-pattern-id>
status: candidate                # candidate | promoted | graveyarded
created: 2026-04-28
last_evidence: 2026-04-29
occurrences: 4                   # total append count below
features:                        # set of feature slugs that contributed evidence
  - feature-orders-events
  - feature-billing-rewrite
held_out_replay: PASS            # PASS | PARTIAL | FAIL | UNTESTED
confidence: medium               # low | medium | high
destination: workspace/meta      # repo | workspace/meta | helix-core | personal
---

# Candidate: <Human Title>

## Pattern
What the repeating pattern is — short.

## Evidence Log
Append-only. Distiller adds one block per occurrence — never rewrites prior entries.

### YYYY-MM-DD — <feature-slug>
- File: <repo>/<path>
- Symbol: <name>
- Notes: free-form

## Held-Out Replay
- Last attempt: YYYY-MM-DD
- Result: PASS | PARTIAL | FAIL
- Notes: which occurrence used as held-out, what reproduced cleanly, what didn't.

## Promotion Gate
- Required: occurrences ≥ 3 AND len(features) ≥ 2 AND held_out_replay = PASS AND quarterly_promotions < 5
- Status: ELIGIBLE | NOT-YET ({reason}) | ELIGIBLE-BUT-CAPPED
- Action: hand off to `/maker` for SKILL.md generation, or wait

## Recommendation
CREATE SKILL | ADD TO EXISTING (<existing-id>) | NOT WORTH IT
```

### `graveyard/{id}.md`

```markdown
---
id: <same-id-as-candidate>
graveyarded: 2026-05-15
reason: <one of: too-bespoke | covered-elsewhere | low-frequency | replay-fails | operator-rejected>
last_status_before: candidate    # candidate | promoted (demoted)
---

# Graveyarded: <Human Title>

## Reason
Operator-supplied prose.

## Don't re-suggest if
- Pattern matches: <fingerprint to compare against future candidates>
```

Distiller MUST check this directory before emitting a new candidate. If a graveyarded id matches a pattern's fingerprint, suppress and note in the session report.

### `usage.jsonl`

Append-only. One record per skill invocation:

```json
{
  "ts": "2026-05-01T10:14:22.000Z",
  "skill_id": "csharp-record-with-validators",
  "session_id": "<copilot-session-id>",
  "workspace": "feature-orders-events",
  "edit_distance": null
}
```

`edit_distance` is the operator's measure of how much the skill output had to be edited before commit. `null` until tooling exists; today nothing writes it. Negative-feedback demotion (high edit distance over N invocations → graveyard) is **not implemented in T2** — schema-ready, not built.

**Writer decision (T5, 2026-04-29):** No agent or hook writes `usage.jsonl` automatically. Considered options:

- *Hook-based* — derive-trace.js could scan trace `tool` records for `Read` of `SKILL.md` paths. Conflates "loaded into context" with "actually used"; produces noisy data that does not feed the demotion gate.
- *Skill-side append* — each SKILL.md instructs the LLM to append a record. Unreliable (LLMs forget); also can't measure edit_distance, which needs post-commit signal.
- *Operator command* — a `/skill-used <id> --edit-distance N` prompt. Friction-heavy; will not be done at the rate needed for demotion.

Decision: defer the writer until a real usage-feedback workflow exists. The schema stays so the file format is stable when we do build it. Until then:

- `/skill-audit` skips the edit-distance section when `usage.jsonl` is empty or absent (already in the prompt).
- Invocation counts, if needed for an audit, can be derived from trace `tool` records at audit time without committing to a writer.
- Edit-distance specifically requires an operator-supplied number; that workflow is a separate future track once skills are being used in anger.

### `audits/{YYYY-Q#}.md`

```markdown
---
quarter: 2026-Q2
promoted_count: 3
graveyarded_count: 1
---

# Audit: 2026-Q2

## Promotions
- {id} — promoted YYYY-MM-DD, evidence count {N} across {M} features
- ...

## Graveyards
- {id} — graveyarded YYYY-MM-DD, reason

## Edit-distance trend
{populated when usage.jsonl has data}
```

Auto-populated by a future quarterly audit prompt; ships empty.

## Promotion gates

A candidate promotes when **all** are true:

1. `occurrences ≥ 3`
2. `len(features) ≥ 2` — same pattern appearing in two distinct features (not three occurrences in one feature)
3. `held_out_replay === 'PASS'` — `/skill-synth` validates the candidate against an unseen occurrence
4. `quarterly_promotions < 5` — read from `audits/{current-quarter}.md`. Hard cap.

If 1–3 pass but 4 fails, candidate stays as `ELIGIBLE-BUT-CAPPED`; operator can override with `/maker --force` (not a T2 deliverable).

If ≥1 fails, candidate stays `candidate` with `Status: NOT-YET ({reason})`.

Demotion (promoted → graveyarded) is operator-driven for now. Auto-demotion via edit distance is documented above as "not built."

## Trigger architecture

The distiller is **not** invoked automatically by the hook chain — distillation requires LLM reasoning and is too expensive for a 30s sessionEnd timeout. The hook chain only **detects when distillation is due** and surfaces a reminder.

### sessionEnd heuristic

`helix/.github/hooks/scripts/distill-trigger.js` runs at sessionEnd, after `derive-trace.js`. It reads the active workspace's state and emits a `distill_trigger` state-delta + a stderr reminder when **any** of:

- `phase.current === 'distill'` — actively in distill phase
- `phase.last_completed === 'review'` — review just finished, distill is next

Edge case: trigger fires every sessionEnd while the heuristic matches. No idempotency. Operator dismisses by running `/distill` (which advances phase) or by accepting the noise. This is intentional — under-triggering risks losing distillation entirely; over-triggering is a stderr line.

The script does **not** invoke the distiller agent. It records that distillation is due and prints a reminder. The agent runs in the next interactive session when the operator types `/distill` or asks "@distiller distill this session."

### Manual `/distill` prompt

`helix/.github/prompts/distill.prompt.md` is the operator-facing entry. Routes to the `distiller` agent with the active workspace as context. Always available; cheaper than waiting for the heuristic.

### Workspace-close trigger

Plan §6 listed "workspace-close" as a trigger. Helix doesn't currently have a clean signal for workspace closure (no `status: closed` field). For T2 this is the manual `/distill` path — operator runs it before archiving a workspace. A future close trigger can extend `distill-trigger.js` once workspace state has a closure signal.

## Distiller agent contract changes

The distiller agent (`helix/.github/agents/distiller.agent.md`) gains two responsibilities:

1. **Before emitting a promotion candidate**, read `.helix/skills/candidates/{id}.md`. If it exists, **append** to its Evidence Log instead of creating a duplicate. Update frontmatter (`occurrences`, `features`, `last_evidence`).
2. **Before suggesting any candidate**, scan `.helix/skills/graveyard/`. If a graveyarded entry's "Don't re-suggest if" fingerprint matches the pattern, suppress and note in the session distill report under `## Suppressed (graveyarded)`.

Held-out replay continues to be `/skill-synth`'s responsibility. Distiller calls it when `occurrences ≥ 3 AND features ≥ 2`, then records the result in the candidate's `Held-Out Replay` section.

## What's deliberately NOT in T2

- **Auto-promotion.** Even when all gates pass, distiller writes `Recommendation: CREATE SKILL` and stops. Operator runs `/maker` manually. We do not want skills created without a human signing off.
- **Edit-distance demotion.** No `usage.jsonl` consumer exists today. Schema is in place; the consumer is future work.
- **Two-pass synthesis (Haiku ID + Opus eval).** Plan §6 + Week 6 work; not T2.
- **Quarterly audit automation.** Audits dir ships empty; a future `/skill-audit` prompt populates it.
- **Cross-repo aggregation across separate meta-repos.** `.helix/skills/` is per-meta-repo. If multiple meta-repos exist on one operator's machine, evidence does not cross meta-repo boundaries. Acceptable now; revisit when Helix is used by multiple teams.

## Hard constraints (carry forward)

- No git hooks. Trigger lives in Copilot CLI sessionEnd.
- No `.claude/` additions.
- Tech-agnostic: distiller does not assume any language/framework. Patterns are scanned by `/skill-synth` against whatever the operator has.
- Distiller writes Markdown + JSONL only — no binary state, no hidden DBs.
