# Helix Label Schema

The sibling file an operator writes to label a captured trace. Closes the Layer 2 loop in `eval-strategy.md` — every captured trace gets one judgement file so the corpus is aggregable.

## Where it lives

- Path: `<repo-root>/.helix/traces/<session-id>.label.yml` (sibling to `<session-id>.jsonl`).
- Created via the `/hc-label-session` slash command.
- Schema is **closed**: unknown keys are rejected. New dimensions require a schema bump, not silent extension.

## Fields (all required)

- `correctness` — enum `match | partial | wrong`. Did the produced artifact match what the operator would have written?
- `rework` — enum `none | minor | major`. How much did the operator have to redo afterwards?
- `notes` — string, single-line, may be empty (`""`). Free-form. What went wrong or right.

Token cost, latency, and session metadata are **not** in this file. They are read from the trace at analysis time.

## Why these three (and not more)

- The mechanical fields (tokens, wall-clock, agent counts) are deterministic — labelling them adds no signal.
- `correctness` and `rework` are the two judgements only the operator can make — one about the artifact, one about the cost of fixing it.
- `notes` captures the qualitative reason a future reviewer needs to interpret the score.

## Why single-line `notes`

The default Helix YAML reader does not parse block scalars (`|`). Single-line quoted strings round-trip safely through every reader Helix ships today. If a richer parser is wired in later, this constraint relaxes; until then, fold paragraphs into one line.

## Example (well-formed)

```yaml
correctness: partial
rework: minor
notes: "Architect produced a sound slice plan but missed the auth-coupling on /orders. Caught at review; one extra round-trip."
```

## Non-examples (rejected)

Missing required field:

```yaml
correctness: match
rework: none
# notes missing → reject. Use notes: "" if you have nothing to say.
```

Out-of-enum value:

```yaml
correctness: ok        # reject — must be match | partial | wrong
rework: none
notes: ""
```

Extra unknown field:

```yaml
correctness: match
rework: none
notes: ""
reviewer: sam          # reject — schema is closed
```

## Promotion path

When ≥20 labelled traces exist across ≥3 distinct workspaces (per `eval-strategy.md`), the labelled set graduates to `helix/evals/golden/`. The schema in this file is the contract those scores aggregate against — keep it stable, evolve it deliberately.
