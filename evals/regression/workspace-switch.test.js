// Verifies that switching the active workspace cleans up old projections
// (Step 3 of skill-projection-and-simplification-plan.md) without touching
// hc-* core or hr-* helix-reusable skills.

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
  throw new Error(`No PowerShell executable found.`);
}

function seedTwoWorkspaceMetaRepo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-switch-'));

  writeFile(path.join(root, '.helix', 'context-providers.yml'), [
    'providers:', '  code_review_graph:', '    mode: off', '',
  ].join('\n'));

  writeFile(path.join(root, 'helix-repos.yml'), [
    'schema_version: 1',
    'defaults:',
    '  default_branch: main',
    'repos:',
    '  - id: service-a',
    '    remote: https://github.com/example-org/service-a.git',
    '    local_path: workspaces/alpha/repos/service-a',
    '    default_branch: main',
    '  - id: service-b',
    '    remote: https://github.com/example-org/service-b.git',
    '    local_path: workspaces/beta/repos/service-b',
    '    default_branch: main',
    '',
  ].join('\n'));

  function workspaceManifest(id, repoId) {
    return [
      'schema_version: 1',
      `id: ${id}`,
      `display_name: ${id}`,
      'status: draft',
      'mode: interactive',
      'workflow: full-rpi',
      'phase:',
      '  current: setup',
      '  last_completed: null',
      'repos:',
      `  - repo_id: ${repoId}`,
      '    role: primary',
      '    branch: main',
      '',
    ].join('\n');
  }

  writeFile(path.join(root, 'workspaces', 'alpha', 'workspace.yml'), workspaceManifest('alpha', 'service-a'));
  writeFile(path.join(root, 'workspaces', 'beta', 'workspace.yml'), workspaceManifest('beta', 'service-b'));

  writeFile(path.join(root, 'templates', 'mental-model.md.template'), [
    '# Mental Model', '',
    '## Domain Glossary', '',
    '## Flag Inventory', '',
    '## Coupling Map', '',
    '## Behavior Conditions', '',
    '## State Diagrams', '',
    '## Surprise Log', '',
  ].join('\n'));

  // Core + reusable skills that must survive switches.
  writeFile(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md'), [
    '---', 'name: hc-workspace-sync', 'managed-by: helix-core',
    'description: Sync a Helix workspace', 'argument-hint: "Workspace name"',
    'user-invocable: true', '---', '', '# Workspace Sync', '',
  ].join('\n'));
  writeFile(path.join(root, '.github', 'skills', 'hr-shared-thing', 'SKILL.md'), [
    '---', 'name: hr-shared-thing', 'managed-by: helix-runtime',
    'description: Pre-existing reusable', 'user-invocable: true', '---', '', '# HR\n',
  ].join('\n'));

  // Repo skills.
  for (const [wsid, repoId, skillName] of [
    ['alpha', 'service-a', 'alpha-only-skill'],
    ['beta',  'service-b', 'beta-only-skill'],
  ]) {
    const repoRoot = path.join(root, 'workspaces', wsid, 'repos', repoId);
    writeFile(path.join(repoRoot, 'AGENTS.md'), `# ${repoId}\n`);
    fs.mkdirSync(path.join(repoRoot, 'tests'), { recursive: true });
    writeFile(path.join(repoRoot, '.github', 'skills', skillName, 'SKILL.md'), [
      '---', `name: ${skillName}`, 'managed-by: helix-runtime',
      `description: Test skill ${skillName}`, '---', '', `# ${skillName}\n`,
    ].join('\n'));
  }

  return root;
}

function runSetup(root, workspaceId) {
  return runPowerShellFile(SETUP_SCRIPT, ['-Workspace', workspaceId, '-TargetRoot', root], HELIX_ROOT);
}

test('workspace-switch-cleanup: switching from alpha to beta removes alpha projections', () => {
  const root = seedTwoWorkspaceMetaRepo();

  let r = runSetup(root, 'alpha');
  assert.equal(r.status, 0, `alpha setup failed:\n${r.stdout}\n${r.stderr}`);
  assert.ok(fs.existsSync(path.join(root, '.github', 'skills', 'service-a-alpha-only-skill')),
    'alpha projection should exist after first setup');

  r = runSetup(root, 'beta');
  assert.equal(r.status, 0, `beta setup failed:\n${r.stdout}\n${r.stderr}`);

  assert.equal(
    fs.existsSync(path.join(root, '.github', 'skills', 'service-a-alpha-only-skill')),
    false,
    'alpha projection should be removed after switching to beta'
  );
  assert.ok(
    fs.existsSync(path.join(root, '.github', 'skills', 'service-b-beta-only-skill')),
    'beta projection should be created'
  );
});

test('workspace-switch-preserves-core: hc-* and hr-* skills are untouched across switches', () => {
  const root = seedTwoWorkspaceMetaRepo();

  let r = runSetup(root, 'alpha');
  assert.equal(r.status, 0, `alpha setup failed:\n${r.stdout}\n${r.stderr}`);
  r = runSetup(root, 'beta');
  assert.equal(r.status, 0, `beta setup failed:\n${r.stdout}\n${r.stderr}`);

  assert.ok(fs.existsSync(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md')),
    'hc-workspace-sync must survive workspace switch');
  assert.ok(fs.existsSync(path.join(root, '.github', 'skills', 'hr-shared-thing', 'SKILL.md')),
    'hr-shared-thing must survive workspace switch');
});
