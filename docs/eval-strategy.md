# Helix Eval Strategy

How Helix is evaluated, why the strategy is split into two layers, and what is deliberately *not* being measured yet.

## Why two layers (and not "9 golden scenarios")

Plan §11 originally called for 9 designed scenarios + a baseline + Week 6 comparison. That sizing assumes a corpus of real Helix runs to draw from. As of 2026-04-28 we have one real workspace (enterprise, not committable) and no committed runs. A baseline assembled from one real source plus eight synthetic-from-imagination scenarios measures imagination, not Helix — and a Week 6 comparison against it would be theatre.

Two layers solve the asymmetry:

| Layer | Builds against | Builds when | What it catches |
|---|---|---|---|
| **Regression tests** | Helix machinery only — no Copilot runs | Now (Week 2) | Plumbing breakage: hooks, schemas, sanitization, gate logic |
| **Quality baseline** | Real captured traces | Passively over Weeks 3-5 | Output quality drift between Helix versions |

Regression covers what we can test deterministically without invoking an LLM. Quality covers what only real usage can answer — and we wait for usage instead of inventing it.

## Layer 1 — Regression tests

- Lives in `helix/evals/regression/`. Run via `node --test helix/evals/regression/*.test.js`.
- Pure unit tests against hook scripts and runtime helpers. No Copilot CLI, no LLM, no network.
- Targets behaviour Helix is responsible for and that has a single correct answer.

What's covered:

- `pre-tool-use.js` denies each entry in the dangerous-command list, allows benign commands.
- `helix-runtime.redactText` redacts known secret shapes (GitHub tokens, Bearer headers, `--password`/`--token` args).
- `helix-runtime.truncateText` caps at the documented length and appends the truncation marker.
- `helix-runtime.sanitizeForLog` recurses into nested objects/arrays.
- `helix-runtime.parseSimpleYaml` handles the workspace.yml shapes used by `getWorkspaceState` (workflow + phase fields).
- `helix-runtime.getWorkspaceState` returns the documented default (`workflow: full-rpi`) when manifest is missing, and reads the declared workflow when present (opaque string passthrough — not enum-constrained).
- `helix-runtime.appendStateDelta` writes a record matching the schema in `trace-schema.md`.
- `derive-trace.deriveTraceRecords` against fixture events + deltas: emits expected kinds, attributes nested events to innermost subagent, computes `latency_ms` from start/end timestamps, sanitizes nested tool-args, carries workspace/workflow/phase/crg_mode forward via state-delta join.
- Planned trace regression coverage: source event references for Copilot CLI Lens (`copilot_session_id`, `source_event_id`, `source_event_index`, `source_event_type`, `source_tool_call_id`) and missing-Helix overlay fallback behavior in Lens.

What's deliberately NOT covered:

- "Did the orchestrator dispatch to the right agent for this intent?" — needs a Copilot run, non-deterministic, belongs in Layer 2.
- "Was the curated context bundle good enough?" — quality judgement, not a regression.
- End-to-end flow through CRG → curate-context → architect. Stubbing the whole stack reproduces wiring but not behaviour.

Adding a regression test is cheap. The bar is: *the answer is binary, and the failure mode is "we broke the plumbing"*. Anything fuzzier belongs in Layer 2.

## Layer 2 — Quality baseline (passive capture)

The trace pipeline (`derive-trace.js` → `.helix/traces/<session-id>.jsonl`) already produces a structured record of every Helix-driven Copilot session. Use it as the corpus.

Process:

1. Each real Helix session through Weeks 3-5 emits a trace at `sessionEnd`. No extra effort required.
2. The operator tags trace files with `/label-session` when the session closes. The prompt writes a sibling file `.helix/traces/<session-id>.label.yml` using the closed schema in `label-schema.md`: `correctness`, `rework`, `notes`.
3. By Week 6, the labelled set IS the baseline. Re-run the same intents through Helix at Week 6 (where reproducible) and compare; for non-reproducible runs, score Week 6 sessions blind against the same rubric and check distribution.

Rubric fields (recorded in the label file):

- `correctness` — did the produced artifact (PRD/design/slice/skill) match what the operator would have written? `match | partial | wrong`
- `token_cost` — total tokens across the session (read from trace, not labelled)
- `wall_clock_ms` — session duration (read from trace, not labelled)
- `rework` — did the operator have to redo significant work afterwards? `none | minor | major`
- `notes` — single-line free-form text, what went wrong or right

Why this works:

- Every label is grounded in a real session, not an imagined one.
- The corpus grows as Helix is used. Week 6 has whatever weeks of usage produced — small but real.
- Token-cost and latency are mechanical; correctness and rework are the judgements only the operator can make.
- New workspaces added later expand the corpus without changing the rubric.

When the corpus reaches ~20 labelled sessions across ≥3 distinct workspaces, the rubric is stable enough to define explicit golden scenarios drawn from it. Until then, treat Layer 2 as a labelled diary, not a scorecard.

## Promotion path: when Layer 2 becomes "golden scenarios"

Trigger: ≥20 labelled traces, ≥3 distinct workspaces, ≥1 cross-repo workspace, ≥6 months of varied usage. At that point:

- Sample 9 traces (3 small / 3 medium / 3 large by repo count) from the labelled set.
- Anonymise the prompts and slice names where needed for sharing.
- Commit them to `helix/evals/golden/` with the rubric judgements as ground truth.
- Future Helix changes are scored by replaying those traces through derive-trace + comparing.

This is when `helix/docs/golden-scenarios.md` becomes a real document. Today it would be fiction.

## Hard constraints (carry forward)

- Eval harness must not require Copilot CLI to be running. Layer 1 is local; Layer 2 is post-hoc against captured traces.
- Tech-agnostic: no language/framework/runner baked into the rubric. Verification commands in slices come from the operator's ecosystem.
- No `.claude/` additions. Eval lives alongside Helix (`helix/evals/`).
- Verbosity: each test file ≤200 lines; if a test needs more setup than that, the system under test is the problem, not the test.
