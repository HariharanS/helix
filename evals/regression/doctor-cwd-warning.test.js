// Verifies that doctor.ps1 emits a non-failing warning when invoked from a
// non-meta-root CWD. Helix sessions are expected to run with the meta-root
// as CWD so hosts discover .github/skills, .github/prompts, and AGENTS.md.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const DOCTOR_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'doctor.ps1');

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

function runPowerShellFile(scriptPath, args, cwd) {
  const candidates = process.platform === 'win32' ? ['pwsh.exe', 'powershell.exe'] : ['pwsh'];
  for (const command of candidates) {
    const result = spawnSync(
      command,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args],
      { cwd, encoding: 'utf8' }
    );
    if (result.error && result.error.code === 'ENOENT') continue;
    return { command, ...result };
  }
  throw new Error(`No PowerShell executable found. Tried: ${candidates.join(', ')}`);
}

function seedMinimalMetaRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-doctor-cwd-'));

  writeFile(path.join(root, '.helix', 'context-providers.yml'), [
    'providers:',
    '  code_review_graph:',
    '    mode: off',
    '',
  ].join('\n'));

  writeFile(path.join(root, '.helix', 'install-state.yml'), [
    'schema_version: 1',
    'installed_at: 2026-05-04T00:00:00Z',
    '',
  ].join('\n'));

  writeFile(path.join(root, 'helix-repos.yml'), [
    'schema_version: 1',
    'defaults:',
    '  default_branch: main',
    'repos: []',
    '',
  ].join('\n'));

  return root;
}

test('doctor-cwd: warns when invoked from a non-meta-root CWD', () => {
  const metaRoot = seedMinimalMetaRoot();
  const otherCwd = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-doctor-cwd-other-'));

  const r = runPowerShellFile(DOCTOR_SCRIPT, ['-TargetRoot', metaRoot], otherCwd);
  const combined = `${r.stdout || ''}\n${r.stderr || ''}`;

  assert.match(
    combined,
    /non-meta-root CWD/i,
    `expected CWD warning. Got:\n${combined}`
  );
});

test('doctor-cwd: does not warn when invoked from the meta-root CWD', () => {
  const metaRoot = seedMinimalMetaRoot();

  const r = runPowerShellFile(DOCTOR_SCRIPT, ['-TargetRoot', metaRoot], metaRoot);
  const combined = `${r.stdout || ''}\n${r.stderr || ''}`;

  assert.doesNotMatch(
    combined,
    /non-meta-root CWD/i,
    `did not expect CWD warning. Got:\n${combined}`
  );
});
