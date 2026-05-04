// Verifies that hc-resume.agent.md describes a successful path that does not
// require .helix/memory/. This is a source/grep-level test — we are not
// running an LLM here. We assert that:
//   1. The agent file marks memory as optional.
//   2. The agent file does not gate resume on memory.
//   3. A synthetic workspace with no .helix/memory/ produces a resume.yml
//      that the agent file's documented sources can satisfy.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const SETUP_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'setup-workspace.ps1');
const RESUME_AGENT = path.join(HELIX_ROOT, '.github', 'agents', 'hc-resume.agent.md');

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

function runPwshFile(scriptPath, args, cwd) {
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

function seedWorkspaceWithoutMemory(workspaceId = 'demo') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-resume-no-memory-'));

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
    '    remote: https://github.com/example-org/service-a.git',
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

  writeFile(path.join(root, 'templates', 'mental-model.md.template'), '# Mental Model\n');

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

test('resume-without-memory: agent file does not require .helix/memory/', () => {
  const text = fs.readFileSync(RESUME_AGENT, 'utf8');

  // Memory references must be marked optional. The plan requires the word
  // "optional" near the memory references; assert it appears in the same
  // paragraph as `.helix/memory`.
  const memoryLine = text.split(/\r?\n/).findIndex(l => /\.helix\/memory/.test(l));
  assert.notEqual(memoryLine, -1, 'agent file must mention .helix/memory');

  // Search a small window around the memory mention for "optional".
  const lines = text.split(/\r?\n/);
  const window = lines.slice(Math.max(0, memoryLine - 2), memoryLine + 3).join('\n');
  assert.match(window, /optional/i, 'memory references must be marked optional');

  // Defensive: agent file MUST NOT phrase memory as a hard precondition.
  assert.doesNotMatch(text, /memory.*(is|must be) required/i);
  assert.doesNotMatch(text, /requires? .*\.helix\/memory/i);
});

test('resume-without-memory: synthetic workspace with no .helix/memory has all primary sources', () => {
  const root = seedWorkspaceWithoutMemory();
  const r = runPwshFile(SETUP_SCRIPT, ['-Workspace', 'demo', '-TargetRoot', root], HELIX_ROOT);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  // No memory directory should exist for this workspace fixture.
  assert.equal(fs.existsSync(path.join(root, '.helix', 'memory')), false,
    '.helix/memory should NOT exist in this fixture');

  // Primary resume sources should still exist:
  assert.ok(fs.existsSync(path.join(root, '.helix', 'active-workspace.yml')),
    'active-workspace.yml missing');
  assert.ok(fs.existsSync(path.join(root, 'workspaces', 'demo', 'workspace.yml')),
    'workspace.yml missing');
  assert.ok(fs.existsSync(path.join(root, 'workspaces', 'demo', 'resume.yml')),
    'resume.yml missing — primary state source must be present even without memory');

  const resume = fs.readFileSync(path.join(root, 'workspaces', 'demo', 'resume.yml'), 'utf8');
  assert.match(resume, /^phase:$/m);
  assert.match(resume, /^ {2}current: discovery$/m);
});
