# Copilot Session Overlay Plan

How Helix should annotate GitHub Copilot CLI sessions without becoming a parallel session recorder.

## Decision

Copilot CLI remains the primary owner of session history. Helix adds process context as small local files.

| Layer | Owns | Storage |
|---|---|---|
| Copilot CLI | raw prompts, assistant messages, tools, turns, subagents, hook spans, files, checkpoints | `~/.copilot/session-state/<session-id>/` and `~/.copilot/session-store.db` |
| Helix | workspace, workflow, phase, CRG mode, trace labels, distillation triggers, hook telemetry | `<repo-root>/.helix/*.jsonl` and `<repo-root>/.helix/traces/` |
| Copilot CLI Lens | read-only presentation and local cache if needed | its own app state, not Helix hook state |

GitHub documents the Copilot session store as a structured subset of the full session files. `/chronicle reindex` rebuilds that store from the session files. Helix should therefore treat Copilot files as canonical and Copilot SQLite as a read/search index for Lens, not as a dependency inside hooks.

Reference: <https://docs.github.com/en/enterprise-cloud@latest/copilot/concepts/agents/copilot-cli/chronicle>

## Non-Goals

- Do not make Helix write a SQLite database for session overlay in the hook path.
- Do not duplicate full Copilot prompts, responses, tool results, or transcripts in Helix state.
- Do not require Copilot CLI Lens to know Helix exists before it can show normal Copilot sessions.
- Do not fail a Copilot session because a Helix telemetry hook failed.

## Current Problems

### P1: `crg-sweep` hook crash

`crg-sweep.js` imports `logEvent` from `helix-runtime.js`, but `helix-runtime.js` does not export it. Running the configured hook fails with `TypeError: logEvent is not a function`.

Fix:

1. Add an exported hook telemetry helper in `helix-runtime.js`, for example `appendHookEvent`.
2. Write operational hook records to `.helix/hook-events.jsonl`.
3. Do not write CRG sweep status to `.helix/state-deltas.jsonl`; it is operational telemetry, not lifecycle state.
4. Wrap `crg-sweep.js` `main()` in `try/catch` so hook failures are surfaced to stderr but never abort the host.
5. Add a regression test for `crg-sweep` with `mode: off`, `mode: mcp` without active workspace, and missing CRG runtime.

### P2: trace records lack stable source references

`derive-trace.js` emits useful Helix-enriched records, but Copilot CLI Lens already builds a span tree from raw Copilot events. Lens needs deterministic source keys to attach Helix metadata to those spans.

Fix:

1. Add source fields to every derived record:

   ```json
   {
     "copilot_session_id": "<session-id>",
     "source_event_id": "<copilot-event-id-or-null>",
     "source_event_index": 42,
     "source_event_type": "tool.execution_complete",
     "source_tool_call_id": "<toolCallId-or-null>"
   }
   ```

2. Add start references for span-like records:

   ```json
   {
     "kind": "subagent",
     "source_event_type": "subagent.completed",
     "source_event_id": "<completed-event-id>",
     "source_start_event_id": "<started-event-id>",
     "source_tool_call_id": "<toolCallId>"
   }
   ```

3. Preserve current derived fields (`workspace`, `workflow`, `phase`, `crg_mode`, `agent`, `tokens`, `latency_ms`) so existing trace consumers continue to work.

## Derivation Model

Target algorithm for `derive-trace.js`:

1. Resolve the Copilot session id from `~/.copilot/session-state/*/workspace.yaml` by matching `cwd` or `git_root` to the Helix repo root.
2. Stream `events.jsonl` in append order.
3. Read `state-deltas.jsonl` as the small Helix side log, or stream it with a cursor if it grows.
4. Carry forward the active Helix context using the most recent delta with `delta.ts <= event.ts`.
5. Maintain only bounded indexes:
   - `subagentStartByToolCallId`
   - `activeSubagentStack`
6. Emit trace records to `<trace>.tmp` line by line.
7. Rename `<trace>.tmp` to `.helix/traces/<session-id>.jsonl` atomically.
8. Append `.helix/session-index.jsonl` after a successful trace write.

This keeps hooks dependency-light and avoids coupling to `session-store.db`, which may be updated by Copilot around session end.

## Helix Session Index

Add a small bridge file for tools such as Copilot CLI Lens:

Path: `<repo-root>/.helix/session-index.jsonl`

One record per known Copilot session:

```json
{
  "schema_version": 1,
  "copilot_session_id": "<session-id>",
  "repo_root": "C:/path/to/meta-repo",
  "workspace": "feature-orders-events",
  "workflow": "full-rpi",
  "phase": "implementation",
  "crg_mode": "mcp",
  "first_seen_at": "2026-04-29T10:00:00.000Z",
  "last_seen_at": "2026-04-29T10:45:00.000Z",
  "trace_path": ".helix/traces/<session-id>.jsonl",
  "label_path": ".helix/traces/<session-id>.label.yml"
}
```

Writers may append duplicate `copilot_session_id` rows; readers should use the last valid row for a session. This preserves append-only behavior and avoids in-hook rewrite complexity.

## Copilot CLI Lens Contract

Lens should show Copilot sessions even when Helix is absent.

Backend shape:

```json
{
  "sessionId": "<session-id>",
  "helix": {
    "available": false
  }
}
```

When Helix is available:

```json
{
  "sessionId": "<session-id>",
  "helix": {
    "available": true,
    "workspace": "feature-orders-events",
    "workflow": "full-rpi",
    "phase": "implementation",
    "tracePath": ".helix/traces/<session-id>.jsonl",
    "labelPath": ".helix/traces/<session-id>.label.yml",
    "label": {
      "correctness": "partial",
      "rework": "minor",
      "notes": "..."
    }
  }
}
```

Lens fallback tests:

- no `.helix/` directory
- `.helix/` exists but no `session-index.jsonl`
- session index exists but no record for this session
- trace exists but label is missing
- trace has unknown future fields
- trace line is malformed

Unknown or missing Helix data must degrade to `helix.available = false` or a partial overlay warning. It must not break project lists, session lists, or raw Copilot timelines.

## Implementation Order

1. Done: fix P1 hook telemetry and harden `crg-sweep`.
2. Done: add source references to `derive-trace` records and tests.
3. Done: add `.helix/session-index.jsonl` append writer after successful trace generation.
4. Convert `derive-trace` from full in-memory event arrays to streaming output.
5. Update Copilot CLI Lens to discover Helix overlays from `session-index.jsonl` and trace files.
6. Add Lens fallback tests for no-overlay and partial-overlay sessions.
7. Run Helix regression tests and a manual Lens session against a project with and without Helix.

## Handoff Notes

- Current implementation has completed steps 1-3. Steps 4-7 remain.
- The accepted direction is file-first Helix state, Copilot SQLite only in Lens/read paths, no SQLite dependency in hooks.
- The trace schema should remain backward-compatible: add fields, do not rename existing ones.
- If future scale requires indexing Helix traces, create a Lens-owned cache first. Add a Helix SQLite store only after append-only files become a measured bottleneck.
