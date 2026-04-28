# Helix evals

Two layers, per `helix/docs/eval-strategy.md`:

- `regression/` — deterministic unit tests against hook scripts and runtime helpers. Run on every change.
- `baselines/` — labelled real-session traces captured passively. Populated from `.helix/traces/<id>.jsonl` during normal Helix usage.

## Run regression

```sh
node --test helix/evals/regression/*.test.js
```

No external dependencies. Requires Node ≥18 (native `node:test`). The glob is needed because `node --test <dir>` treats the path as a module, not a test directory.

## Add a regression test

The bar: the answer is binary and the failure mode is "we broke the plumbing". If the test would need an LLM run to score, it doesn't belong here — see Layer 2 in `eval-strategy.md`.
