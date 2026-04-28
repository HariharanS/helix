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
  isoTimestamp,
  readHookInput,
  readYamlFile,
  redactText,
  truncateText,
} = require('./helix-runtime');

const COPILOT_HOME = process.env.COPILOT_HOME || path.join(os.homedir(), '.copilot');

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
  const rl = readline.createInterface({
    input: fs.createReadStream(filePath, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line)); } catch { /* skip malformed */ }
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

// Build a map of toolCallId -> open subagent.started event so tool/turn events
// inside a subagent span can be attributed to that agent.
function indexSubagents(events) {
  const open = new Map();
  const closed = new Map();
  for (const e of events) {
    if (e.type === 'subagent.started') {
      open.set(e.data?.toolCallId, { started: e, ended: null });
    } else if (e.type === 'subagent.completed') {
      const id = e.data?.toolCallId;
      const span = open.get(id);
      if (span) {
        span.ended = e;
        closed.set(id, span);
        open.delete(id);
      }
    }
  }
  return { open, closed };
}

// Build a stack-aware lookup: for any timestamp, which subagent is innermost?
// Walks events once, tracks (start, end) intervals for each subagent.
function makeSubagentResolver(events) {
  const intervals = []; // { start, end, agent, model, toolCallId, parentTurnId }
  const turnByCallId = new Map();
  let currentTurn = null;
  for (const e of events) {
    if (e.type === 'assistant.turn_start') currentTurn = e.data?.turnId || null;
    if (e.type === 'assistant.turn_end') currentTurn = null;
    if (e.type === 'subagent.started') {
      turnByCallId.set(e.data?.toolCallId, currentTurn);
    }
  }
  const open = new Map();
  for (const e of events) {
    if (e.type === 'subagent.started') {
      open.set(e.data?.toolCallId, e);
    } else if (e.type === 'subagent.completed') {
      const id = e.data?.toolCallId;
      const start = open.get(id);
      if (start) {
        intervals.push({
          start: Date.parse(start.timestamp),
          end: Date.parse(e.timestamp),
          agent: start.data?.agentName || start.data?.agentDisplayName || null,
          model: e.data?.model || null,
          totalTokens: e.data?.totalTokens ?? null,
          totalToolCalls: e.data?.totalToolCalls ?? null,
          toolCallId: id,
          parentTurnId: turnByCallId.get(id) || null,
        });
        open.delete(id);
      }
    }
  }
  return function resolveAt(ts) {
    const t = Date.parse(ts);
    let best = null;
    for (const iv of intervals) {
      if (iv.start <= t && t <= iv.end) {
        if (!best || iv.start > best.start) best = iv;
      }
    }
    return best;
  };
}

function sanitizeToolArgs(args) {
  if (!args || typeof args !== 'object') return null;
  const out = {};
  for (const [k, v] of Object.entries(args)) {
    if (typeof v === 'string') {
      out[k] = truncateText(redactText(v));
    } else {
      out[k] = v;
    }
  }
  return out;
}

function deriveTraceRecords(events, deltas) {
  const resolveCtx = makeContextResolver(deltas);
  const resolveSubagent = makeSubagentResolver(events);
  const records = [];

  for (const e of events) {
    const ts = e.timestamp;
    if (!ts) continue;
    const ctx = resolveCtx(ts);
    const subagent = resolveSubagent(ts);

    switch (e.type) {
      case 'user.message':
        records.push({
          ts,
          kind: 'prompt',
          ...ctx,
          agent: subagent?.agent || 'top-level',
          content: truncateText(redactText(e.data?.content || '')),
        });
        break;

      case 'assistant.message': {
        const reqs = (e.data?.toolRequests || []).map(r => r.name).filter(Boolean);
        records.push({
          ts,
          kind: 'assistant',
          ...ctx,
          agent: subagent?.agent || 'top-level',
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
          ...ctx,
          agent: subagent?.agent || 'top-level',
          tool_name: e.data?.toolName || null,
          tool_call_id: e.data?.toolCallId || null,
          args,
          outcome: e.data?.outcome || (e.data?.error ? 'error' : 'success'),
        });
        break;
      }

      case 'subagent.completed': {
        const startTs = events.find(
          x => x.type === 'subagent.started' && x.data?.toolCallId === e.data?.toolCallId
        )?.timestamp;
        records.push({
          ts,
          kind: 'subagent',
          ...ctx,
          agent: e.data?.agentName || e.data?.agentDisplayName || null,
          model: e.data?.model || null,
          tokens: e.data?.totalTokens ?? null,
          tool_calls: e.data?.totalToolCalls ?? null,
          latency_ms: startTs ? Date.parse(ts) - Date.parse(startTs) : null,
          outcome: e.data?.outcome || 'success',
        });
        break;
      }

      case 'session.model_change':
        records.push({ ts, kind: 'model_change', ...ctx, model: e.data?.newModel || null });
        break;

      case 'session.warning':
        records.push({
          ts,
          kind: 'warning',
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

    const records = deriveTraceRecords(events, deltas);
    const tracePath = path.join(repoRoot, '.helix', 'traces', `${sessionId}.jsonl`);
    const body = records.map(r => JSON.stringify(r)).join('\n') + (records.length ? '\n' : '');
    writeAtomic(tracePath, body);
    process.stderr.write(
      `[derive-trace] wrote ${records.length} records to .helix/traces/${sessionId}.jsonl\n`
    );
  } catch (err) {
    // Hooks must never abort the host. Surface and exit 0.
    process.stderr.write(`[derive-trace] ${err.stack || err.message}\n`);
  }
}

main();
