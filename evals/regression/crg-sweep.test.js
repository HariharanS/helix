// Asserts the CRG sweep hook is telemetry-only for skipped paths and does not
// crash sessionEnd when CRG is disabled, unconfigured, or unavailable.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const SCRIPT = path.resolve(__dirname, '..', '..', '.github', 'hooks', 'scripts', 'crg-sweep.js');
const { main } = require(SCRIPT);

function tmpRepo() {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-crg-'));
  fs.mkdirSync(path.join(repo, '.github', 'hooks'), { recursive: true });
  return repo;
}

function writeFile(filePath, body) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, body, 'utf8');
}

function withHookCwd(repo, fn) {
  const previous = process.cwd();
  process.chdir(path.join(repo, '.github', 'hooks'));
  try {
    fn();
  } finally {
    process.chdir(previous);
  }
}

function writeCrgMode(repo, mode) {
  writeFile(
    path.join(repo, '.helix', 'context-providers.yml'),
    `providers:\n  code_review_graph:\n    mode: ${mode}\n`
  );
}

function readHookEvents(repo) {
  const filePath = path.join(repo, '.helix', 'hook-events.jsonl');
  return fs.readFileSync(filePath, 'utf8').trim().split('\n').map(JSON.parse);
}

function hookInput() {
  return {
    timestamp: Date.parse('2026-04-28T12:00:00.000Z'),
    hookName: 'sessionEnd',
    sessionId: 'session-1',
  };
}

test('crg-sweep: mode off writes skipped hook telemetry', () => {
  const repo = tmpRepo();
  writeCrgMode(repo, 'off');

  withHookCwd(repo, () => {
    main({ readHookInput: hookInput });
  });

  const [event] = readHookEvents(repo);
  assert.equal(event.event_type, 'crgSweep');
  assert.equal(event.skipped, true);
  assert.equal(event.reason, 'mode=off');
  assert.equal(fs.existsSync(path.join(repo, '.helix', 'state-deltas.jsonl')), false);
});

test('crg-sweep: mcp mode without active workspace writes skipped telemetry', () => {
  const repo = tmpRepo();
  writeCrgMode(repo, 'mcp');

  withHookCwd(repo, () => {
    main({ readHookInput: hookInput });
  });

  const [event] = readHookEvents(repo);
  assert.equal(event.event_type, 'crgSweep');
  assert.equal(event.skipped, true);
  assert.equal(event.reason, 'no-active-workspace');
});

test('crg-sweep: missing CRG runtime writes skipped telemetry before git work', () => {
  const repo = tmpRepo();
  writeCrgMode(repo, 'mcp');
  writeFile(path.join(repo, '.helix', 'active-workspace.yml'), 'active: feature-x\n');
  fs.mkdirSync(path.join(repo, 'workspaces', 'feature-x', 'repos', 'app', '.git'), { recursive: true });

  withHookCwd(repo, () => {
    main({
      readHookInput: hookInput,
      findPythonRunner: () => null,
    });
  });

  const [event] = readHookEvents(repo);
  assert.equal(event.event_type, 'crgSweep');
  assert.equal(event.skipped, true);
  assert.equal(event.reason, 'no-python-runner');
  assert.equal(event.workspace, 'feature-x');
});
