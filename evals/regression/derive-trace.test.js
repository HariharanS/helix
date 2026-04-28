// Asserts the join logic in derive-trace: kind mapping, nested-subagent
// attribution via the active stack, latency computation, recursive sanitization
// of tool args, and state-delta context propagation.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SCRIPT = path.resolve(__dirname, '..', '..', '.github', 'hooks', 'scripts', 'derive-trace.js');
const { deriveTraceRecords, sanitizeToolArgs } = require(SCRIPT);

const baselineDelta = {
  ts: '2026-04-28T12:00:00.000Z',
  delta_type: 'session_baseline',
  workspace: 'feature-x',
  workflow: 'full-rpi',
  phase: 'implementation',
  crg_mode: 'mcp',
};

function ev(type, ts, data = {}) {
  return { type, timestamp: ts, data };
}

test('emits prompt record for user.message', () => {
  const events = [ev('user.message', '2026-04-28T12:01:00.000Z', { content: 'hello' })];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  assert.equal(recs.length, 1);
  assert.equal(recs[0].kind, 'prompt');
  assert.equal(recs[0].agent, 'top-level');
  assert.equal(recs[0].content, 'hello');
});

test('carries workspace/workflow/phase from state-delta into trace records', () => {
  const events = [ev('user.message', '2026-04-28T12:01:00.000Z', { content: 'hi' })];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  assert.equal(recs[0].workspace, 'feature-x');
  assert.equal(recs[0].workflow, 'full-rpi');
  assert.equal(recs[0].phase, 'implementation');
  assert.equal(recs[0].crg_mode, 'mcp');
});

test('attributes events inside a subagent span to that subagent', () => {
  const events = [
    ev('user.message', '2026-04-28T12:01:00.000Z', { content: 'go' }),
    ev('subagent.started', '2026-04-28T12:01:01.000Z', { toolCallId: 'c1', agentName: 'architect' }),
    ev('tool.execution_complete', '2026-04-28T12:01:02.000Z', {
      toolName: 'read_file', toolCallId: 't1', arguments: { path: 'x.md' }, outcome: 'success',
    }),
    ev('subagent.completed', '2026-04-28T12:01:05.000Z', {
      toolCallId: 'c1', agentName: 'architect', model: 'claude-sonnet-4-6',
      totalTokens: 1000, totalToolCalls: 1, outcome: 'success',
    }),
    ev('tool.execution_complete', '2026-04-28T12:01:06.000Z', {
      toolName: 'write_file', toolCallId: 't2', arguments: { path: 'y.md' },
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  const promptRec = recs.find(r => r.kind === 'prompt');
  const innerTool = recs.find(r => r.kind === 'tool' && r.tool_call_id === 't1');
  const outerTool = recs.find(r => r.kind === 'tool' && r.tool_call_id === 't2');
  assert.equal(promptRec.agent, 'top-level');
  assert.equal(innerTool.agent, 'architect');
  assert.equal(outerTool.agent, 'top-level', 'event after subagent.completed must be top-level again');
});

test('innermost subagent wins when nested', () => {
  const events = [
    ev('subagent.started', '2026-04-28T12:01:00.000Z', { toolCallId: 'outer', agentName: 'orchestrator' }),
    ev('subagent.started', '2026-04-28T12:01:01.000Z', { toolCallId: 'inner', agentName: 'implementer' }),
    ev('tool.execution_complete', '2026-04-28T12:01:02.000Z', {
      toolName: 'edit_file', toolCallId: 't1', arguments: { path: 'a' },
    }),
    ev('subagent.completed', '2026-04-28T12:01:03.000Z', {
      toolCallId: 'inner', agentName: 'implementer',
    }),
    ev('tool.execution_complete', '2026-04-28T12:01:04.000Z', {
      toolName: 'edit_file', toolCallId: 't2', arguments: { path: 'b' },
    }),
    ev('subagent.completed', '2026-04-28T12:01:05.000Z', {
      toolCallId: 'outer', agentName: 'orchestrator',
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  const t1 = recs.find(r => r.kind === 'tool' && r.tool_call_id === 't1');
  const t2 = recs.find(r => r.kind === 'tool' && r.tool_call_id === 't2');
  assert.equal(t1.agent, 'implementer', 'innermost active subagent attributes the event');
  assert.equal(t2.agent, 'orchestrator', 'after inner completes, outer is innermost');
});

test('subagent record carries latency_ms = end - start', () => {
  const events = [
    ev('subagent.started', '2026-04-28T12:00:00.000Z', { toolCallId: 'c1', agentName: 'reviewer' }),
    ev('subagent.completed', '2026-04-28T12:00:18.402Z', {
      toolCallId: 'c1', agentName: 'reviewer', model: 'claude-sonnet-4-6',
      totalTokens: 13280, totalToolCalls: 7, outcome: 'success',
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  const sub = recs.find(r => r.kind === 'subagent');
  assert.equal(sub.latency_ms, 18402);
  assert.equal(sub.tokens, 13280);
  assert.equal(sub.tool_calls, 7);
  assert.equal(sub.model, 'claude-sonnet-4-6');
});

test('subagent record latency_ms is null when no matching start', () => {
  const events = [
    ev('subagent.completed', '2026-04-28T12:00:18.402Z', {
      toolCallId: 'orphan', agentName: 'reviewer',
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  assert.equal(recs[0].latency_ms, null);
});

test('sanitizeToolArgs recurses into nested objects and arrays', () => {
  const args = sanitizeToolArgs({
    path: 'src/foo.js',
    headers: { Authorization: 'Bearer abc.def-ghi' },
    patches: [{ old: '--password=hunter2', new_: 'safe' }],
  });
  assert.equal(args.path, 'src/foo.js');
  assert.match(args.headers.Authorization, /Bearer \[REDACTED\]/);
  assert.match(args.patches[0].old, /--password=\[REDACTED\]/);
  assert.equal(args.patches[0].new_, 'safe');
});

test('sanitizeToolArgs returns null for non-object input', () => {
  assert.equal(sanitizeToolArgs(null), null);
  assert.equal(sanitizeToolArgs(undefined), null);
  assert.equal(sanitizeToolArgs('string'), null);
});

test('tool record sanitizes nested args via the join (regression for shallow-redact bug)', () => {
  const events = [
    ev('tool.execution_complete', '2026-04-28T12:01:00.000Z', {
      toolName: 'apply_patch', toolCallId: 't1',
      arguments: {
        patches: [{ command: 'curl --token shh-shh https://api.example' }],
      },
      outcome: 'success',
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  const tool = recs[0];
  assert.match(tool.args.patches[0].command, /--token=\[REDACTED\]/);
});

test('skips event types not in the documented kind taxonomy', () => {
  const events = [
    ev('session.start', '2026-04-28T12:00:00.000Z', { cwd: '/repo' }),
    ev('hook.invoked', '2026-04-28T12:00:01.000Z', { name: 'sessionStart' }),
    ev('assistant.turn_start', '2026-04-28T12:00:02.000Z', { turnId: 't1' }),
    ev('user.message', '2026-04-28T12:00:03.000Z', { content: 'hi' }),
    ev('assistant.turn_end', '2026-04-28T12:00:04.000Z', { turnId: 't1' }),
    ev('session.shutdown', '2026-04-28T12:00:05.000Z', {}),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  assert.equal(recs.length, 1, 'only user.message should produce a record');
  assert.equal(recs[0].kind, 'prompt');
});

test('emits assistant record with tool_requests + truncated content_preview', () => {
  const events = [
    ev('assistant.message', '2026-04-28T12:01:00.000Z', {
      content: 'x'.repeat(500),
      toolRequests: [{ name: 'read_file' }, { name: 'write_file' }],
    }),
  ];
  const recs = deriveTraceRecords(events, [baselineDelta]);
  const a = recs[0];
  assert.equal(a.kind, 'assistant');
  assert.deepEqual(a.tool_requests, ['read_file', 'write_file']);
  assert.ok(a.content_preview.length <= 200 + '...<truncated>'.length);
  assert.ok(a.content_preview.endsWith('...<truncated>'));
});

test('phase changes via successive deltas reflect in records after the change ts', () => {
  const deltas = [
    baselineDelta,
    {
      ts: '2026-04-28T12:05:00.000Z',
      delta_type: 'phase_change',
      phase: 'review',
    },
  ];
  const events = [
    ev('user.message', '2026-04-28T12:01:00.000Z', { content: 'before' }),
    ev('user.message', '2026-04-28T12:06:00.000Z', { content: 'after' }),
  ];
  const recs = deriveTraceRecords(events, deltas);
  assert.equal(recs[0].phase, 'implementation');
  assert.equal(recs[1].phase, 'review');
  assert.equal(recs[1].workspace, 'feature-x', 'workspace must carry forward across phase change');
});
