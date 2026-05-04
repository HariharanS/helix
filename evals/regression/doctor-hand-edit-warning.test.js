// Verifies that doctor.ps1 warns when a projected SKILL.md has been
// hand-edited at the meta-root, instead of being edited in the source repo.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const SETUP_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'setup-workspace.ps1');
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

function runPowerShellInline(command, cwd) {
  const candidates = process.platform === 'win32' ? ['pwsh.exe', 'powershell.exe'] : ['pwsh'];
  for (const exe of candidates) {
    const result = spawnSync(
      exe,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      { cwd, encoding: 'utf8' }
    );
    if (result.error && result.error.code === 'ENOENT') continue;
    return { command: exe, ...result };
  }
  throw new Error(`No PowerShell executable found.`);
}

function seedMetaRepoWithSkill(workspaceId = 'demo', repoId = 'service-a', skillName = 'code-review') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-doctor-handedit-'));

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
    `  - id: ${repoId}`,
    `    remote: https://github.com/example-org/${repoId}.git`,
    `    local_path: workspaces/${workspaceId}/repos/${repoId}`,
    `    default_branch: main`,
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
    `  - repo_id: ${repoId}`,
    '    role: primary',
    '    branch: main',
    '',
  ].join('\n'));

  writeFile(path.join(root, 'templates', 'mental-model.md.template'), [
    '# Mental Model', '',
    '## Domain Glossary', '',
    '## Flag Inventory', '',
    '## Coupling Map', '',
    '## Behavior Conditions', '',
    '## State Diagrams', '',
    '## Surprise Log', '',
  ].join('\n'));

  writeFile(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md'), [
    '---', 'name: hc-workspace-sync', 'managed-by: helix-core',
    'description: Sync a Helix workspace', 'argument-hint: "Workspace name"',
    'user-invocable: true', '---', '', '# Workspace Sync', '',
  ].join('\n'));

  const repoRoot = path.join(root, 'workspaces', workspaceId, 'repos', repoId);
  writeFile(path.join(repoRoot, 'AGENTS.md'), `# ${repoId}\n`);
  writeFile(path.join(repoRoot, '.github', 'skills', skillName, 'SKILL.md'), [
    '---',
    `name: ${skillName}`,
    'managed-by: helix-runtime',
    `description: Test skill ${skillName}`,
    '---',
    '',
    `# ${skillName}`,
    '',
    'Original body content.',
    '',
  ].join('\n'));

  return { root, workspaceId, repoId, skillName };
}

test('doctor-hand-edit: warns when a projected SKILL.md is hand-edited at the meta-root', () => {
  const { root, workspaceId, repoId, skillName } = seedMetaRepoWithSkill();

  const setup = runPowerShellFile(SETUP_SCRIPT, ['-Workspace', workspaceId, '-TargetRoot', root], HELIX_ROOT);
  assert.equal(setup.status, 0, `setup failed:\n${setup.stdout}\n${setup.stderr}`);

  const projectedFolder = path.join(root, '.github', 'skills', `${repoId}-${skillName}`);
  const projectedSkillMd = path.join(projectedFolder, 'SKILL.md');
  assert.ok(fs.existsSync(projectedSkillMd), 'projection should exist after setup');

  const relax = runPowerShellInline(
    `Import-Module '${path.join(HELIX_ROOT, 'scripts', 'Helix.Tools.psm1').replace(/'/g, "''")}' -Force; ` +
    `Set-HelixSkillFolderReadOnly -Folder '${projectedFolder.replace(/'/g, "''")}' -ReadOnly $false`,
    HELIX_ROOT
  );
  assert.equal(relax.status, 0, `failed to relax readonly:\n${relax.stdout}\n${relax.stderr}`);

  const tampered = fs.readFileSync(projectedSkillMd, 'utf8') + '\n<!-- hand-edit by tester -->\n';
  fs.writeFileSync(projectedSkillMd, tampered, 'utf8');

  const doctor = runPowerShellFile(DOCTOR_SCRIPT, ['-TargetRoot', root], root);
  const combined = `${doctor.stdout || ''}\n${doctor.stderr || ''}`;

  assert.match(
    combined,
    /hand-edited/i,
    `expected hand-edit warning. Got:\n${combined}`
  );
  assert.match(
    combined,
    new RegExp(`${repoId}-${skillName}|${repoId}|${skillName}`),
    `expected warning to reference the affected skill. Got:\n${combined}`
  );
});
