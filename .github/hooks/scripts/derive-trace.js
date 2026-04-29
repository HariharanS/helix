#!/usr/bin/env node

// Derives a Helix trace from Copilot CLI's native events.jsonl joined with
// Helix's state-deltas.jsonl. Runs at sessionEnd. Idempotent.
//
// Inputs:
//   ~/.copilot/session-state/<id>/events.jsonl   (Copilot — LLM/tool/subagent activity)
//   ~/.copilot/session-state/<id>/workspace.yaml (Copilot — cwd/git_root for session match)
//   <repo-root>/.helix/state-deltas.jsonl        (Helix  — workspace/workflow/phase context)
//
// Output:
//   <repo-root>/.helix/traces/<session-id>.jsonl

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');

const {
  getRepoRoot,
  getStateDeltaPath,
  readHookInput,
  readYamlFile,
  redactText,
  sanitizeForLog,
  truncateText,
} = require('./helix-runtime');

const COPILOT_HOME = process.env.COPILOT_HOME || path.join(os.homedir(), '.copilot');
const SOURCE_EVENT_INDEX = Symbol('helixSourceEventIndex');

function pathsEqual(a, b) {
  if (!a || !b) return false;
  return path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase();
}

// Find the Copilot session whose workspace.yaml cwd matches our repoRoot, with
// the most recently modified events.jsonl. Hook input does not carry sessionId,
// so we resolve by cwd + recency.
function findCopilotSessionId(repoRoot) {
  const stateDir = path.join(COPILOT_HOME, 'session-state');
  if (!fs.existsSync(stateDir)) return null;
  const candidates = [];
  for (const id of fs.readdirSync(stateDir)) {
    const wsYaml = path.join(stateDir, id, 'workspace.yaml');
    const eventsPath = path.join(stateDir, id, 'events.jsonl');
    if (!fs.existsSync(wsYaml) || !fs.existsSync(eventsPath)) continue;
    const yaml = readYamlFile(wsYaml);
    const sessionCwd = yaml?.cwd || yaml?.git_root || '';
    if (!pathsEqual(sessionCwd, repoRoot)) continue;
    candidates.push({ id, mtime: fs.statSync(eventsPath).mtimeMs });
  }
  if (candidates.length === 0) return null;
  candidates.sort((a, b) => b.mtime - a.mtime);
  return candidates[0].id;
}

async function readJsonlLines(filePath) {
  if (!fs.existsSync(filePath)) return [];
  const out = [];
  let lineIndex = 0;
  const rl = readline.createInterface({
    input: fs.createReadStream(filePath, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    const currentIndex = lineIndex;
    lineIndex += 1;
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        continue;
      }
      Object.defineProperty(parsed, SOURCE_EVENT_INDEX, {
        value: currentIndex,
        enumerable: false,
      });
      out.push(parsed);
    } catch {
      // skip malformed
    }
  }
  return out;
}

function sortDeltasAsc(deltas) {
  return [...deltas].sort((a, b) => Date.parse(a.ts) - Date.parse(b.ts));
}

// Build a function that returns the active Helix context as of timestamp `ts`.
// Carries workspace/workflow/phase forward from prior deltas (snapshot model).
function makeContextResolver(deltas) {
  const sorted = sortDeltasAsc(deltas);
  let cursor = 0;
  let ctx = { workspace: null, workflow: null, phase: null, crg_mode: null };

  return function resolveAt(ts) {
    const eventMs = Date.parse(ts);
    while (cursor < sorted.length && Date.parse(sorted[cursor].ts) <= eventMs) {
      const d = sorted[cursor];
      if (d.workspace !== undefined) ctx.workspace = d.workspace;
      if (d.workflow !== undefined) ctx.workflow = d.workflow;
      if (d.phase !== undefined) ctx.phase = d.phase;
      if (d.crg_mode !== undefined) ctx.crg_mode = d.crg_mode;
      cursor += 1;
    }
    return { ...ctx };
  };
}

// Index every subagent.started by toolCallId so subagent.completed handlers and
// nested-attribution lookups are O(1) instead of linear scans of the events list.
function indexSubagentStarts(events) {
  const byId = new Map();
  for (let index = 0; index < events.length; index += 1) {
    const e = events[index];
    if (e.type === 'subagent.started' && e.data?.toolCallId) {
      byId.set(e.data.toolCallId, {
        event: e,
        index: getSourceEventIndex(e, index),
      });
    }
  }
  return byId;
}

function getSourceEventId(event) {
  return event?.id ?? event?.event_id ?? event?.eventId ?? null;
}

function getSourceEventIndex(event, fallbackIndex) {
  if (Number.isInteger(event?.[SOURCE_EVENT_INDEX])) {
    return event[SOURCE_EVENT_INDEX];
  }
  return Number.isInteger(fallbackIndex) ? fallbackIndex : null;
}

function getSourceToolCallId(event) {
  return event?.data?.toolCallId ?? event?.toolCallId ?? event?.tool_call_id ?? null;
}

function sourceRefs(event, fallbackIndex, sessionId) {
  return {
    copilot_session_id: sessionId || null,
    source_event_id: getSourceEventId(event),
    source_event_index: getSourceEventIndex(event, fallbackIndex),
    source_event_type: event?.type || null,
    source_tool_call_id: getSourceToolCallId(event),
  };
}

function sanitizeToolArgs(args) {
  if (!args || typeof args !== 'object') return null;
  return sanitizeForLog(args);
}

// Walks events in append-order (time-ordered by Copilot) and emits trace records.
// Maintains an active-subagent stack inline so each non-subagent event is attributed
// to the innermost open subagent without per-event interval scans.
function deriveTraceRecords(events, deltas, options = {}) {
  const sessionId = options.sessionId || null;
  const resolveCtx = makeContextResolver(deltas);
  const startById = indexSubagentStarts(events);
  const activeStack = []; // [{ toolCallId, agent }]
  const records = [];

  for (let eventIndex = 0; eventIndex < events.length; eventIndex += 1) {
    const e = events[eventIndex];
    const ts = e.timestamp;
    if (!ts) continue;

    if (e.type === 'subagent.started') {
      if (e.data?.toolCallId) {
        activeStack.push({
          toolCallId: e.data.toolCallId,
          agent: e.data?.agentName || e.data?.agentDisplayName || null,
        });
      }
      continue;
    }

    const ctx = resolveCtx(ts);
    const innermost = activeStack[activeStack.length - 1];
    const agentForChild = innermost?.agent || 'top-level';
    const refs = sourceRefs(e, eventIndex, sessionId);

    switch (e.type) {
      case 'user.message':
        records.push({
          ts,
          kind: 'prompt',
          ...refs,
          ...ctx,
          agent: agentForChild,
          content: truncateText(redactText(e.data?.content || '')),
        });
        break;

      case 'assistant.message': {
        const reqs = (e.data?.toolRequests || []).map(r => r.name).filter(Boolean);
        records.push({
          ts,
          kind: 'assistant',
          ...refs,
          ...ctx,
          agent: agentForChild,
          tool_requests: reqs,
          content_preview: truncateText(redactText(e.data?.content || ''), 200),
        });
        break;
      }

      case 'tool.execution_complete': {
        const args = sanitizeToolArgs(e.data?.arguments);
        records.push({
          ts,
          kind: 'tool',
          ...refs,
          ...ctx,
          agent: agentForChild,
          tool_name: e.data?.toolName || null,
          tool_call_id: e.data?.toolCallId || null,
          args,
          outcome: e.data?.outcome || (e.data?.error ? 'error' : 'success'),
        });
        break;
      }

      case 'subagent.completed': {
        const id = e.data?.toolCallId;
        const start = id ? startById.get(id) : null;
        const startTs = start?.event?.timestamp || null;
        records.push({
          ts,
          kind: 'subagent',
          ...refs,
          ...ctx,
          agent: e.data?.agentName || e.data?.agentDisplayName || null,
          tool_call_id: id || null,
          model: e.data?.model || null,
          tokens: e.data?.totalTokens ?? null,
          tool_calls: e.data?.totalToolCalls ?? null,
          latency_ms: startTs ? Date.parse(ts) - Date.parse(startTs) : null,
          outcome: e.data?.outcome || 'success',
          source_start_event_id: start ? getSourceEventId(start.event) : null,
          source_start_event_index: start ? start.index : null,
        });
        const idx = activeStack.findIndex(f => f.toolCallId === id);
        if (idx !== -1) activeStack.splice(idx, 1);
        break;
      }

      case 'session.model_change':
        records.push({ ts, kind: 'model_change', ...refs, ...ctx, model: e.data?.newModel || null });
        break;

      case 'session.warning':
        records.push({
          ts,
          kind: 'warning',
          ...refs,
          ...ctx,
          message: truncateText(redactText(e.data?.message || ''), 200),
          warning_type: e.data?.warningType || null,
        });
        break;

      default:
        // session.start / session.shutdown / turn / hook / point — skip; they
        // are present in Copilot's events.jsonl and don't add Helix value.
        break;
    }
  }
  return records;
}

function writeAtomic(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp`;
  fs.writeFileSync(tmp, content, 'utf8');
  fs.renameSync(tmp, filePath);
}

function getSessionIndexPath(repoRoot) {
  return path.join(repoRoot, '.helix', 'session-index.jsonl');
}

function appendJsonlRecord(filePath, record) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.appendFileSync(filePath, `${JSON.stringify(record)}\n`, 'utf8');
}

function latestDeltaContext(deltas) {
  const sorted = sortDeltasAsc(deltas);
  const ctx = { workspace: null, workflow: null, phase: null, crg_mode: null };
  for (const d of sorted) {
    if (d.workspace !== undefined) ctx.workspace = d.workspace;
    if (d.workflow !== undefined) ctx.workflow = d.workflow;
    if (d.phase !== undefined) ctx.phase = d.phase;
    if (d.crg_mode !== undefined) ctx.crg_mode = d.crg_mode;
  }
  return ctx;
}

function latestRecordContext(records) {
  for (let i = records.length - 1; i >= 0; i -= 1) {
    const record = records[i];
    if (
      record.workspace !== undefined ||
      record.workflow !== undefined ||
      record.phase !== undefined ||
      record.crg_mode !== undefined
    ) {
      return {
        workspace: record.workspace ?? null,
        workflow: record.workflow ?? null,
        phase: record.phase ?? null,
        crg_mode: record.crg_mode ?? null,
      };
    }
  }
  return { workspace: null, workflow: null, phase: null, crg_mode: null };
}

function validTimestamp(value) {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value));
}

function sessionTimeBounds(events, records) {
  const eventTimes = events.map(event => event?.timestamp).filter(validTimestamp);
  const recordTimes = records.map(record => record?.ts).filter(validTimestamp);
  const times = eventTimes.length ? eventTimes : recordTimes;
  const fallback = new Date().toISOString();
  return {
    first_seen_at: times[0] || fallback,
    last_seen_at: times[times.length - 1] || fallback,
  };
}

function buildSessionIndexRecord(repoRoot, sessionId, events, deltas, records) {
  const deltaCtx = latestDeltaContext(deltas);
  const recordCtx = latestRecordContext(records);
  const times = sessionTimeBounds(events, records);
  return {
    schema_version: 1,
    copilot_session_id: sessionId,
    repo_root: path.resolve(repoRoot),
    workspace: recordCtx.workspace ?? deltaCtx.workspace,
    workflow: recordCtx.workflow ?? deltaCtx.workflow,
    phase: recordCtx.phase ?? deltaCtx.phase,
    crg_mode: recordCtx.crg_mode ?? deltaCtx.crg_mode,
    first_seen_at: times.first_seen_at,
    last_seen_at: times.last_seen_at,
    trace_path: `.helix/traces/${sessionId}.jsonl`,
    label_path: `.helix/traces/${sessionId}.label.yml`,
  };
}

function appendSessionIndexRecord(repoRoot, record) {
  appendJsonlRecord(getSessionIndexPath(repoRoot), record);
}

async function main() {
  try {
    readHookInput(); // drain stdin even though we don't use the payload
    const repoRoot = getRepoRoot();
    const sessionId = findCopilotSessionId(repoRoot);
    if (!sessionId) {
      process.stderr.write(`[derive-trace] no Copilot session matched cwd=${repoRoot}\n`);
      return;
    }

    const eventsPath = path.join(COPILOT_HOME, 'session-state', sessionId, 'events.jsonl');
    const events = await readJsonlLines(eventsPath);
    const deltas = await readJsonlLines(getStateDeltaPath(repoRoot));

    const records = deriveTraceRecords(events, deltas, { sessionId });
    const tracePath = path.join(repoRoot, '.helix', 'traces', `${sessionId}.jsonl`);
    const body = records.map(r => JSON.stringify(r)).join('\n') + (records.length ? '\n' : '');
    writeAtomic(tracePath, body);
    try {
      appendSessionIndexRecord(
        repoRoot,
        buildSessionIndexRecord(repoRoot, sessionId, events, deltas, records)
      );
    } catch (err) {
      process.stderr.write(`[derive-trace] failed to append session-index: ${err.message || err}\n`);
    }
    process.stderr.write(
      `[derive-trace] wrote ${records.length} records to .helix/traces/${sessionId}.jsonl${records.length ? '\n  -> run /label-session to label this trace (correctness/rework/notes)' : ''}\n`
    );
  } catch (err) {
    // Hooks must never abort the host. Surface and exit 0.
    process.stderr.write(`[derive-trace] ${err.stack || err.message}\n`);
  }
}

if (require.main === module) main();

module.exports = {
  appendSessionIndexRecord,
  buildSessionIndexRecord,
  deriveTraceRecords,
  getSessionIndexPath,
  indexSubagentStarts,
  makeContextResolver,
  readJsonlLines,
  sanitizeToolArgs,
};
