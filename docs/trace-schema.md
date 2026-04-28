# Helix Trace Schema

How Helix records what happened during a Copilot CLI session, and how the data flows from raw sources to a derived trace.

## Sources of truth (do not duplicate)

| Source | Path | Owns |
|---|---|---|
| Copilot CLI | `~/.copilot/session-state/<session-id>/events.jsonl` | LLM/tool/subagent/turn/hook spans, models, tokens, tool args/results |
| Copilot CLI | `~/.copilot/session-store.db` | Sessions, turns, files, checkpoints, FTS5 search |
| Helix | `<repo-root>/.helix/state-deltas.jsonl` | Workspace, workflow, phase, CRG mode — only when state changes |
| Helix | `<repo-root>/.helix/traces/<session-id>.jsonl` | **Derived** — Copilot events ⨝ Helix deltas |

Helix never re-emits what Copilot already records. The state-delta log is append-on-change only.

## State-delta record

Append one when Helix-controlled state changes. Today this happens at `sessionStart` (baseline). Future: phase transitions, workflow changes, slice gates, distillation candidate appends.

```json
{
  "ts": "2026-04-28T14:33:21.000Z",
  "delta_type": "session_baseline",
  "workspace": "feature-orders-events",
  "workflow": "full-rpi",
  "phase": "implementation",
  "last_completed_phase": "tech-design",
  "crg_mode": "mcp",
  "crg_detail": "standard",
  "source": "new"
}
```

`delta_type` values (opaque, extensible): `session_baseline`, `workspace_change`, `phase_change`, `workflow_change`, `crg_change`, `slice_gate`.

## Derived trace record

`derive-trace.js` runs at `sessionEnd`, joins Copilot events with state-deltas using `most-recent delta ≤ event.ts`, sanitizes secrets, and writes one record per Copilot event of interest.

```json
{
  "ts": "2026-04-28T14:33:25.812Z",
  "kind": "subagent",
  "workspace": "feature-orders-events",
  "workflow": "full-rpi",
  "phase": "implementation",
  "crg_mode": "mcp",
  "agent": "implementer",
  "model": "claude-sonnet-4-6",
  "tokens": 13280,
  "tool_calls": 7,
  "latency_ms": 18402,
  "outcome": "success"
}
```

## Field semantics

- `workflow` — opaque string. Default `full-rpi`. **Do not enum-constrain.** Future workflows (test-only on a PR, review-only, design-only) declare their own value; trace consumers group by it.
- `phase` — opaque string. Carries whatever the active workflow uses. `full-rpi` uses `setup | jam | prd | tech-design | task-breakdown | implementation | review | distill`. A future test-only workflow might use `scope | run | report` — the schema doesn't care.
- `agent` — Copilot subagent name (resolved from innermost active `subagent.started` interval), or `top-level` for events outside any subagent.
- `tokens` — present on `subagent` records (always reported by Copilot at completion). May be `null` on other kinds.
- `latency_ms` — `subagent.completed.ts − subagent.started.ts`. May be `null` if either bound is missing.

## Kinds emitted

| `kind` | Source event | Purpose |
|---|---|---|
| `prompt` | `user.message` | User input (sanitized) |
| `assistant` | `assistant.message` | LLM reply preview + tool requests |
| `tool` | `tool.execution_complete` | Tool call name + sanitized args + outcome |
| `subagent` | `subagent.completed` | Agent name, model, tokens, tool count, latency |
| `model_change` | `session.model_change` | Mid-session model switch |
| `warning` | `session.warning` | Warning surfaced |

Skipped (recorded by Copilot, not Helix-additive): `session.start`, `session.shutdown`, `assistant.turn_*`, `tool.execution_start`, `subagent.started`, `hook.*`, `system.notification`.

## Sanitization

Applied at derivation time over Copilot inputs (Copilot does not redact):

- GitHub tokens (`ghp_…`, `gho_…`, `github_pat_…`)
- `Bearer …` headers
- `--password=…`, `--token=…` arguments
- Strings truncated at 400 chars (200 for assistant content previews)

## Session-id resolution

Hook input does not carry the Copilot session id. `derive-trace.js` resolves it by scanning `~/.copilot/session-state/*/workspace.yaml` for the session whose `cwd` matches the meta-repo root, breaking ties by most recently modified `events.jsonl`.

## Idempotency

`derive-trace.js` overwrites `<repo-root>/.helix/traces/<session-id>.jsonl` atomically (write `.tmp`, rename). Re-running the hook regenerates the same content; no append-and-grow risk.
