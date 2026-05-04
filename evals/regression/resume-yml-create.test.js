// Verifies setup-workspace.ps1 seeds workspaces/{id}/resume.yml with phase.current set.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const SETUP_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'setup-workspace.ps1');

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

function seedMetaRepo(workspaceId = 'demo') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-resume-create-'));

  writeFile(path.join(root, '.helix', 'context-providers.yml'), [
    'providers:',
    '  code_review_graph:',
    '    mode: off',
    '',
  ].join('\n'));

  writeFile(path.join(root, 'helix-repos.yml'), [
    'schema_version: 1',
    'defaults:',
    '  default_branch: main',
    'repos:',
    '  - id: service-a',
    `    remote: https://github.com/example-org/service-a.git`,
    `    local_path: workspaces/${workspaceId}/repos/service-a`,
    '    default_branch: main',
    '',
  ].join('\n'));

  writeFile(path.join(root, 'workspaces', workspaceId, 'workspace.yml'), [
    'schema_version: 1',
    `id: ${workspaceId}`,
    `display_name: ${workspaceId}`,
    'status: draft',
    'mode: interactive',
    'workflow: full-rpi',
    'phase:',
    '  current: setup',
    '  last_completed: null',
    'repos:',
    '  - repo_id: service-a',
    '    role: primary',
    '    branch: main',
    'artifacts:',
    '  task_board_dir: task-boards/',
    '  execution_plan_dir: execution-plans/',
    '  decisions_dir: decisions/',
    '',
  ].join('\n'));

  writeFile(path.join(root, 'templates', 'mental-model.md.template'), [
    '# Mental Model', '',
    '## Domain Glossary', '',
  ].join('\n'));

  writeFile(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md'), [
    '---', 'name: hc-workspace-sync', 'managed-by: helix-core',
    'description: Sync a Helix workspace', 'argument-hint: "Workspace name"',
    'user-invocable: true', '---', '', '# Workspace Sync', '',
  ].join('\n'));

  const repoRoot = path.join(root, 'workspaces', workspaceId, 'repos', 'service-a');
  writeFile(path.join(repoRoot, 'AGENTS.md'), '# service-a\n');
  fs.mkdirSync(path.join(repoRoot, 'tests'), { recursive: true });

  return root;
}

test('resume-yml-create: setup-workspace seeds resume.yml with phase.current = discovery', () => {
  const root = seedMetaRepo();
  const r = runPowerShellFile(SETUP_SCRIPT, ['-Workspace', 'demo', '-TargetRoot', root], HELIX_ROOT);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  const resumePath = path.join(root, 'workspaces', 'demo', 'resume.yml');
  assert.ok(fs.existsSync(resumePath), 'resume.yml was not created');
  const text = fs.readFileSync(resumePath, 'utf8');

  assert.match(text, /^schema_version: 1$/m);
  assert.match(text, /^workspace: demo$/m);
  assert.match(text, /^updated_at:/m);
  assert.match(text, /^phase:$/m);
  assert.match(text, /^ {2}current: discovery$/m);
  assert.match(text, /^artifact_paths:$/m);
  assert.match(text, /task_board:.*task-boards/);
});

test('resume-yml-create: re-running setup does not overwrite existing resume.yml fields', () => {
  const root = seedMetaRepo();
  const first = runPowerShellFile(SETUP_SCRIPT, ['-Workspace', 'demo', '-TargetRoot', root], HELIX_ROOT);
  assert.equal(first.status, 0, `first setup failed:\n${first.stdout}\n${first.stderr}`);

  const resumePath = path.join(root, 'workspaces', 'demo', 'resume.yml');
  // Mutate phase.current to verify subsequent setup runs leave it alone
  // (initial-create path is gated on file absence).
  const original = fs.readFileSync(resumePath, 'utf8');
  const mutated = original.replace(/^( {2}current: ).*$/m, '$1implementation');
  fs.writeFileSync(resumePath, mutated, 'utf8');

  const second = runPowerShellFile(SETUP_SCRIPT, ['-Workspace', 'demo', '-TargetRoot', root], HELIX_ROOT);
  assert.equal(second.status, 0, `second setup failed:\n${second.stdout}\n${second.stderr}`);

  const after = fs.readFileSync(resumePath, 'utf8');
  assert.match(after, /^ {2}current: implementation$/m, 'phase.current was overwritten on second setup');
});
