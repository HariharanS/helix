// Asserts the runtime helpers that hook scripts rely on: redaction, truncation,
// recursive sanitization, the minimal YAML parser, workspace-state resolution
// (with the documented defaults), and state-delta append shape.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const RUNTIME = path.resolve(__dirname, '..', '..', '.github', 'hooks', 'scripts', 'helix-runtime.js');
const {
  appendHookEvent,
  appendStateDelta,
  getHookEventPath,
  getStateDeltaPath,
  getWorkspaceState,
  parseSimpleYaml,
  redactText,
  sanitizeForLog,
  truncateText,
} = require(RUNTIME);

function tmpRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-eval-'));
  return dir;
}

function writeFile(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content, 'utf8');
}

test('redactText: GitHub PAT shapes', () => {
  assert.match(redactText('token=ghp_AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQq'), /\[REDACTED_TOKEN\]/);
  assert.match(redactText('use github_pat_AaBbCcDdEeFfGgHhIiJjKkLl_extra'), /\[REDACTED_TOKEN\]/);
});

test('redactText: Bearer + password/token args', () => {
  assert.match(redactText('Authorization: Bearer abc.def-ghi_jkl'), /Bearer \[REDACTED\]/);
  assert.match(redactText('--password=hunter2'), /--password=\[REDACTED\]/);
  assert.match(redactText('--token shh-shh'), /--token=\[REDACTED\]/);
});

test('redactText: leaves benign strings alone', () => {
  assert.equal(redactText('git status'), 'git status');
  assert.equal(redactText(''), '');
});

test('truncateText: caps and marks truncation', () => {
  const long = 'x'.repeat(500);
  const out = truncateText(long, 100);
  assert.equal(out.length, 100 + '...<truncated>'.length);
  assert.ok(out.endsWith('...<truncated>'));
});

test('truncateText: short strings unchanged', () => {
  assert.equal(truncateText('hi', 100), 'hi');
});

test('sanitizeForLog: recurses arrays + objects', () => {
  const out = sanitizeForLog({
    nested: { token: 'Bearer abc.def' },
    list: [{ password: '--password=secret' }],
    plain: 42,
  });
  assert.match(out.nested.token, /Bearer \[REDACTED\]/);
  assert.match(out.list[0].password, /--password=\[REDACTED\]/);
  assert.equal(out.plain, 42);
});

test('parseSimpleYaml: nested keys and scalars', () => {
  const parsed = parseSimpleYaml(`
workflow: full-rpi
phase:
  current: implementation
  last_completed: tech-design
`);
  assert.equal(parsed.workflow, 'full-rpi');
  assert.equal(parsed.phase.current, 'implementation');
  assert.equal(parsed.phase.last_completed, 'tech-design');
});

test('getWorkspaceState: returns nulls when no active workspace', () => {
  const repo = tmpRepo();
  const state = getWorkspaceState(repo);
  assert.deepEqual(state, { workspaceId: null, workflow: null, phase: null, lastCompletedPhase: null });
});

test('getWorkspaceState: defaults workflow to full-rpi when manifest is missing', () => {
  const repo = tmpRepo();
  writeFile(path.join(repo, '.helix', 'active-workspace.yml'), 'active: feature-x\n');
  const state = getWorkspaceState(repo);
  assert.equal(state.workspaceId, 'feature-x');
  assert.equal(state.workflow, 'full-rpi');
  assert.equal(state.phase, null);
});

test('getWorkspaceState: reads declared workflow as opaque string', () => {
  const repo = tmpRepo();
  writeFile(path.join(repo, '.helix', 'active-workspace.yml'), 'active: feature-x\n');
  writeFile(
    path.join(repo, 'workspaces', 'feature-x', 'workspace.yml'),
    'workflow: review-only\nphase:\n  current: scope\n  last_completed: setup\n'
  );
  const state = getWorkspaceState(repo);
  assert.equal(state.workflow, 'review-only');
  assert.equal(state.phase, 'scope');
  assert.equal(state.lastCompletedPhase, 'setup');
});

test('appendStateDelta: writes schema-shaped JSON line', () => {
  const repo = tmpRepo();
  appendStateDelta(repo, 'session_baseline', '2026-04-28T12:00:00.000Z', {
    workspace: 'feature-x',
    workflow: 'full-rpi',
    phase: 'implementation',
    crg_mode: 'mcp',
  });
  const body = fs.readFileSync(getStateDeltaPath(repo), 'utf8');
  const lines = body.trim().split('\n');
  assert.equal(lines.length, 1);
  const rec = JSON.parse(lines[0]);
  assert.equal(rec.ts, '2026-04-28T12:00:00.000Z');
  assert.equal(rec.delta_type, 'session_baseline');
  assert.equal(rec.workspace, 'feature-x');
  assert.equal(rec.workflow, 'full-rpi');
  assert.equal(rec.phase, 'implementation');
  assert.equal(rec.crg_mode, 'mcp');
});

test('appendStateDelta: appends multiple records as separate lines', () => {
  const repo = tmpRepo();
  appendStateDelta(repo, 'session_baseline', '2026-04-28T12:00:00.000Z', { workspace: 'a' });
  appendStateDelta(repo, 'phase_change', '2026-04-28T12:05:00.000Z', { phase: 'review' });
  const lines = fs.readFileSync(getStateDeltaPath(repo), 'utf8').trim().split('\n');
  assert.equal(lines.length, 2);
  assert.equal(JSON.parse(lines[0]).delta_type, 'session_baseline');
  assert.equal(JSON.parse(lines[1]).delta_type, 'phase_change');
});

test('appendHookEvent: writes operational hook telemetry separately from state deltas', () => {
  const repo = tmpRepo();
  appendHookEvent(repo, 'crgSweep', {
    timestamp: Date.parse('2026-04-28T12:00:00.000Z'),
    hookName: 'sessionEnd',
    sessionId: 'session-1',
  }, {
    skipped: true,
    reason: 'mode=off',
    token: 'Bearer abc.def',
  });

  const rec = JSON.parse(fs.readFileSync(getHookEventPath(repo), 'utf8').trim());
  assert.equal(rec.schema_version, 1);
  assert.equal(rec.ts, '2026-04-28T12:00:00.000Z');
  assert.equal(rec.event_type, 'crgSweep');
  assert.equal(rec.hook_name, 'sessionEnd');
  assert.equal(rec.copilot_session_id, 'session-1');
  assert.equal(rec.skipped, true);
  assert.equal(rec.reason, 'mode=off');
  assert.match(rec.token, /Bearer \[REDACTED\]/);
  assert.equal(fs.existsSync(getStateDeltaPath(repo)), false);
});
