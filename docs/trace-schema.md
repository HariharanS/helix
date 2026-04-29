# Helix Trace Schema

How Helix records what happened during a Copilot CLI session, and how the data flows from raw sources to a derived trace.

## Sources of truth (do not duplicate)

| Source | Path | Owns |
|---|---|---|
| Copilot CLI | `~/.copilot/session-state/<session-id>/events.jsonl` | LLM/tool/subagent/turn/hook spans, models, tokens, tool args/results |
| Copilot CLI | `~/.copilot/session-store.db` | Structured subset of session files used for `/chronicle`, history queries, and Lens list/search views |
| Helix | `<repo-root>/.helix/state-deltas.jsonl` | Workspace, workflow, phase, CRG mode — only when state changes |
| Helix | `<repo-root>/.helix/traces/<session-id>.jsonl` | **Derived** — Copilot events ⨝ Helix deltas |
| Helix | `<repo-root>/.helix/session-index.jsonl` | Bridge from Copilot session id to Helix trace/label paths |
| Helix | `<repo-root>/.helix/hook-events.jsonl` | Operational hook telemetry, not lifecycle state |

Helix never re-emits what Copilot already records. The state-delta log is append-on-change only. Copilot SQLite is a read/search index for tools such as Copilot CLI Lens; Helix hooks should not depend on it.

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

## Hook event record

Append one when a hook needs operational telemetry that is not lifecycle state. CRG sweep skipped/triggered status belongs here, not in `state-deltas.jsonl`.

```json
{
  "schema_version": 1,
  "ts": "2026-04-28T14:35:00.000Z",
  "event_type": "crgSweep",
  "hook_name": "sessionEnd",
  "source": "new",
  "copilot_session_id": "3a5811ae-4328-4a25-906b-3787e34d204f",
  "tool_call_id": null,
  "skipped": true,
  "reason": "mode=off"
}
```

## Derived trace record

`derive-trace.js` runs at `sessionEnd`, joins Copilot events with state-deltas using `most-recent delta ≤ event.ts`, sanitizes secrets, and writes one record per Copilot event of interest.

```json
{
  "ts": "2026-04-28T14:33:25.812Z",
  "kind": "subagent",
  "copilot_session_id": "3a5811ae-4328-4a25-906b-3787e34d204f",
  "source_event_id": "event-42",
  "source_event_index": 42,
  "source_event_type": "subagent.completed",
  "source_tool_call_id": "toolu_123",
  "source_start_event_id": "event-17",
  "source_start_event_index": 17,
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

Source reference fields are the target schema for Copilot CLI Lens overlay work. Older trace files may not have them; consumers must fall back gracefully.

## Field semantics

- `workflow` — opaque string. Default `full-rpi`. **Do not enum-constrain.** Future workflows (test-only on a PR, review-only, design-only) declare their own value; trace consumers group by it.
- `phase` — opaque string. Carries whatever the active workflow uses. `full-rpi` uses `setup | jam | prd | tech-design | task-breakdown | implementation | review | distill`. A future test-only workflow might use `scope | run | report` — the schema doesn't care.
- `agent` — Copilot subagent name (resolved from innermost active `subagent.started` interval), or `top-level` for events outside any subagent.
- `tokens` — present on `subagent` records (always reported by Copilot at completion). May be `null` on other kinds.
- `latency_ms` — `subagent.completed.ts − subagent.started.ts`. May be `null` if either bound is missing.
- `copilot_session_id` — Copilot session id that owns the source event.
- `source_event_id` — Copilot event id when present, otherwise `null`.
- `source_event_index` — zero-based line index in `events.jsonl`; stable fallback when event ids are absent.
- `source_event_type` — original Copilot event type, such as `tool.execution_complete`.
- `source_tool_call_id` — Copilot tool call id when the source event has one.
- `source_start_event_id` — for span-like records, the matching start event id when known.
- `source_start_event_index` — for span-like records, the matching start line index when known.

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

## Derivation algorithm

Target implementation:

1. Stream Copilot `events.jsonl` in append order.
2. Carry Helix context forward from `state-deltas.jsonl` using the most recent delta with `delta.ts <= event.ts`.
3. Maintain bounded in-memory state only for subagent attribution (`activeSubagentStack`, `subagentStartByToolCallId`).
4. Write derived records to a temporary trace file line by line, then rename atomically.
5. Append a session bridge row to `.helix/session-index.jsonl` after a successful trace write. Readers use the last valid row for a session id.

The current implementation reads JSONL into arrays, emits source references, writes traces atomically, and appends `session-index.jsonl`. That is acceptable for small traces; streaming output remains the next scale step before Lens relies on large sessions.

## Lens overlay contract

Copilot CLI Lens must treat Helix as optional. Missing `.helix/`, missing trace files, missing labels, malformed trace lines, or unknown future fields must not break normal Copilot session display.

Use [`copilot-session-overlay-plan.md`](./copilot-session-overlay-plan.md) as the implementation plan for Lens overlay integration.

## Idempotency

`derive-trace.js` overwrites `<repo-root>/.helix/traces/<session-id>.jsonl` atomically (write `.tmp`, rename). Re-running the hook regenerates the same content; no append-and-grow risk.
