// Verifies Update-HelixResumeSnapshot deep-merges patches without overwriting
// other fields. Imports Helix.Tools.psm1 directly into a tmp dir.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const HELIX_TOOLS = path.join(HELIX_ROOT, 'scripts', 'Helix.Tools.psm1');

function runPwshFile(scriptPath, cwd) {
  const candidates = process.platform === 'win32' ? ['pwsh.exe', 'powershell.exe'] : ['pwsh'];
  for (const command of candidates) {
    const result = spawnSync(
      command,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      { cwd, encoding: 'utf8' }
    );
    if (result.error && result.error.code === 'ENOENT') continue;
    return { command, ...result };
  }
  throw new Error(`No PowerShell executable found. Tried: ${candidates.join(', ')}`);
}

function makeTmpRoot(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `helix-${prefix}-`));
}

function writePs1(filePath, body) {
  fs.writeFileSync(filePath, body, 'utf8');
}

test('resume-yml-merge: patching a single field preserves others', () => {
  const root = makeTmpRoot('resume-merge');
  fs.mkdirSync(path.join(root, 'workspaces', 'demo'), { recursive: true });

  const psm1 = HELIX_TOOLS;

  // Step 1: create the resume.yml from defaults via a minimal patch.
  const createScript = path.join(root, 'create.ps1');
  writePs1(createScript, [
    `Import-Module '${psm1}' -Force`,
    `Update-HelixResumeSnapshot -HelixRoot '${root}' -WorkspaceId 'demo' -Patch @{`,
    `    phase = @{ current = 'design'; last_completed = 'discovery' }`,
    `    current_task = 'TASK-001'`,
    `    blocked_tasks = @('TASK-007', 'TASK-009')`,
    `    next_action = 'Initial action'`,
    `} | Out-Null`,
  ].join('\n'));
  const create = runPwshFile(createScript, root);
  assert.equal(create.status, 0, `create failed:\n${create.stdout}\n${create.stderr}`);

  const resumePath = path.join(root, 'workspaces', 'demo', 'resume.yml');
  assert.ok(fs.existsSync(resumePath));
  const initial = fs.readFileSync(resumePath, 'utf8');
  assert.match(initial, /^ {2}current: design$/m);
  assert.match(initial, /^ {2}last_completed: discovery$/m);
  assert.match(initial, /^current_task: TASK-001$/m);
  assert.match(initial, /^next_action: "Initial action"$/m);

  // Step 2: patch only next_action; everything else must survive.
  const patchScript = path.join(root, 'patch.ps1');
  writePs1(patchScript, [
    `Import-Module '${psm1}' -Force`,
    `Update-HelixResumeSnapshot -HelixRoot '${root}' -WorkspaceId 'demo' -Patch @{`,
    `    next_action = 'Implement TASK-002'`,
    `} | Out-Null`,
  ].join('\n'));
  const patch = runPwshFile(patchScript, root);
  assert.equal(patch.status, 0, `patch failed:\n${patch.stdout}\n${patch.stderr}`);

  const after = fs.readFileSync(resumePath, 'utf8');
  // Patched field updated.
  assert.match(after, /^next_action: "Implement TASK-002"$/m);
  // Untouched fields preserved.
  assert.match(after, /^ {2}current: design$/m);
  assert.match(after, /^ {2}last_completed: discovery$/m);
  assert.match(after, /^current_task: TASK-001$/m);
  assert.match(after, /TASK-007/);
  assert.match(after, /TASK-009/);
  assert.match(after, /^workspace: demo$/m);
  assert.match(after, /^schema_version: 1$/m);

  // Step 3: deep-merge into a nested map. Patching phase.current must not
  // wipe phase.last_completed.
  const deepScript = path.join(root, 'deep.ps1');
  writePs1(deepScript, [
    `Import-Module '${psm1}' -Force`,
    `Update-HelixResumeSnapshot -HelixRoot '${root}' -WorkspaceId 'demo' -Patch @{`,
    `    phase = @{ current = 'implementation' }`,
    `} | Out-Null`,
  ].join('\n'));
  const deepPatch = runPwshFile(deepScript, root);
  assert.equal(deepPatch.status, 0, `deep patch failed:\n${deepPatch.stdout}\n${deepPatch.stderr}`);

  const final = fs.readFileSync(resumePath, 'utf8');
  assert.match(final, /^ {2}current: implementation$/m);
  assert.match(final, /^ {2}last_completed: discovery$/m, 'deep-merge should preserve sibling map keys');
});
