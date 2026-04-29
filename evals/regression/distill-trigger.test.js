// Asserts the distill-trigger heuristic + the script's end-to-end behaviour:
// emits a `distill_trigger` state-delta when the workspace is in distill phase
// or has just completed review, stays quiet otherwise.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '..', '..', '.github', 'hooks', 'scripts', 'distill-trigger.js');
const { isDistillationDue } = require(SCRIPT);

function tmpRepo() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'helix-eval-distill-'));
}

function writeFile(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content, 'utf8');
}

function setupWorkspace(repo, { workspaceId, phase, lastCompleted, workflow = 'full-rpi' }) {
  if (workspaceId) {
    writeFile(path.join(repo, '.helix', 'active-workspace.yml'), `active: ${workspaceId}\n`);
    if (phase || lastCompleted || workflow) {
      writeFile(
        path.join(repo, 'workspaces', workspaceId, 'workspace.yml'),
        `workflow: ${workflow}\nphase:\n  current: ${phase || ''}\n  last_completed: ${lastCompleted || ''}\n`
      );
    }
  }
  // distill-trigger spawns from <repo>/.github/hooks, so the cwd must exist.
  fs.mkdirSync(path.join(repo, '.github', 'hooks'), { recursive: true });
}

function runTrigger(repo) {
  const res = spawnSync(process.execPath, [SCRIPT], {
    cwd: path.join(repo, '.github', 'hooks'),
    input: '{}',
    encoding: 'utf8',
  });
  return { stdout: res.stdout, stderr: res.stderr, status: res.status };
}

function readDeltas(repo) {
  const p = path.join(repo, '.helix', 'state-deltas.jsonl');
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
}

test('isDistillationDue: phase=distill triggers', () => {
  assert.equal(isDistillationDue({ workspaceId: 'x', phase: 'distill', lastCompletedPhase: 'review' }), true);
});

test('isDistillationDue: lastCompleted=review triggers even when phase has moved on', () => {
  assert.equal(isDistillationDue({ workspaceId: 'x', phase: null, lastCompletedPhase: 'review' }), true);
});

test('isDistillationDue: no active workspace never triggers', () => {
  assert.equal(isDistillationDue({ workspaceId: null, phase: 'distill', lastCompletedPhase: 'review' }), false);
});

test('isDistillationDue: implementation phase does not trigger', () => {
  assert.equal(isDistillationDue({ workspaceId: 'x', phase: 'implementation', lastCompletedPhase: 'tech-design' }), false);
});

test('script emits distill_trigger delta when workspace is in distill phase', () => {
  const repo = tmpRepo();
  setupWorkspace(repo, { workspaceId: 'feature-x', phase: 'distill', lastCompleted: 'review' });
  const res = runTrigger(repo);
  assert.equal(res.status, 0);
  const deltas = readDeltas(repo);
  assert.equal(deltas.length, 1, 'expected exactly one state-delta');
  assert.equal(deltas[0].delta_type, 'distill_trigger');
  assert.equal(deltas[0].workspace, 'feature-x');
  assert.equal(deltas[0].phase, 'distill');
  assert.equal(deltas[0].reason, 'phase_active');
  assert.match(res.stderr, /distillation due/i);
});

test('script emits delta with reason=review_completed when lastCompleted=review', () => {
  const repo = tmpRepo();
  setupWorkspace(repo, { workspaceId: 'feature-x', phase: 'implementation', lastCompleted: 'review' });
  const res = runTrigger(repo);
  assert.equal(res.status, 0);
  const deltas = readDeltas(repo);
  assert.equal(deltas.length, 1);
  assert.equal(deltas[0].reason, 'review_completed');
});

test('script writes nothing when no workspace is active', () => {
  const repo = tmpRepo();
  setupWorkspace(repo, {}); // no workspaceId
  const res = runTrigger(repo);
  assert.equal(res.status, 0);
  assert.equal(readDeltas(repo).length, 0);
});

test('script writes nothing when workspace is mid-implementation', () => {
  const repo = tmpRepo();
  setupWorkspace(repo, { workspaceId: 'feature-x', phase: 'implementation', lastCompleted: 'tech-design' });
  const res = runTrigger(repo);
  assert.equal(res.status, 0);
  assert.equal(readDeltas(repo).length, 0);
  assert.equal(res.stderr, '', 'no reminder when distillation is not due');
});

test('script never throws on missing .helix dir (idempotent first-run)', () => {
  const repo = tmpRepo();
  fs.mkdirSync(path.join(repo, '.github', 'hooks'), { recursive: true });
  const res = runTrigger(repo);
  assert.equal(res.status, 0, 'must exit 0 even when nothing is set up');
});
