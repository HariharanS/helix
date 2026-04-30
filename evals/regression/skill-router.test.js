// Validates deterministic Helix skill routing independent of model behavior.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const RESOLVE_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'resolve-skill.ps1');
const PROMOTE_SCRIPT = path.join(HELIX_ROOT, 'scripts', 'promote-skill.ps1');

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

function runPowerShellFile(scriptPath, args, cwd) {
  const candidates = process.platform === 'win32'
    ? ['pwsh.exe', 'powershell.exe']
    : ['pwsh'];

  for (const command of candidates) {
    const result = spawnSync(
      command,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args],
      { cwd, encoding: 'utf8' }
    );

    if (result.error && result.error.code === 'ENOENT') {
      continue;
    }

    return { command, ...result };
  }

  throw new Error(`No PowerShell executable found. Tried: ${candidates.join(', ')}`);
}

function seedRegistry(skillsYaml) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-skill-router-'));
  writeFile(path.join(root, '.helix', 'skills', 'index.yml'), [
    'schema_version: 1',
    'updated_at: 2026-04-30T00:00:00Z',
    'active_workspace: demo',
    'skills:',
    skillsYaml,
    '',
  ].join('\n'));
  return root;
}

function resolveSkill(root, args = []) {
  const result = runPowerShellFile(RESOLVE_SCRIPT, ['-TargetRoot', root, ...args], HELIX_ROOT);
  assert.equal(
    result.status,
    0,
    `resolve-skill failed via ${result.command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`
  );
  return JSON.parse(result.stdout).skill_use;
}

test('resolver prefers projected hr skill over repo-local candidate', () => {
  const root = seedRegistry([
    '  - id: hr-payment-contract-fixtures',
    '    name: payment-contract-fixtures',
    '    status: projected',
    '    origin:',
    '      kind: runtime',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    path: .github/skills/hr-payment-contract-fixtures/SKILL.md',
    '    projected_path: .github/skills/hr-payment-contract-fixtures/SKILL.md',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Build PaymentRequest contract fixtures',
    '    requires_skill_use_record: true',
    '  - id: hr-service-a-payment-contract-fixtures',
    '    name: payment-contract-fixtures',
    '    status: candidate',
    '    origin:',
    '      kind: repo-local',
    '      workspace_id: demo',
    '      repo_id: service-a',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Build PaymentRequest contract fixtures',
    '    requires_skill_use_record: true',
  ].join('\n'));

  const skillUse = resolveSkill(root, ['-RepoId', 'service-a', '-Path', 'tests/ContractTests.cs', '-Task', 'payment contract fixtures']);
  assert.equal(skillUse.selected_skill, 'hr-payment-contract-fixtures');
  assert.equal(skillUse.status, 'projected');
  assert.equal(skillUse.fallback, 'projected');
  assert.equal(skillUse.source_path, '.github/skills/hr-payment-contract-fixtures/SKILL.md');
});

test('resolver falls back to repo-local candidate when no projected skill exists', () => {
  const root = seedRegistry([
    '  - id: hr-payment-contract-fixtures',
    '    name: payment-contract-fixtures',
    '    status: candidate',
    '    origin:',
    '      kind: repo-local',
    '      workspace_id: demo',
    '      repo_id: service-a',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Build PaymentRequest contract fixtures',
    '    requires_skill_use_record: true',
  ].join('\n'));

  const skillUse = resolveSkill(root, ['-RepoId', 'service-a', '-Path', 'tests/ContractTests.cs', '-Task', 'payment contract fixtures']);
  assert.equal(skillUse.selected_skill, 'hr-payment-contract-fixtures');
  assert.equal(skillUse.status, 'candidate');
  assert.equal(skillUse.fallback, 'repo-local');
  assert.equal(skillUse.source_path, 'workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md');
});

test('resolver returns disambiguation when equal candidates match', () => {
  const root = seedRegistry([
    '  - id: hr-contract-fixtures-a',
    '    name: contract-fixtures',
    '    status: candidate',
    '    origin:',
    '      kind: repo-local',
    '      repo_id: service-a',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/contract-fixtures-a/SKILL.md',
    '    path: workspaces/demo/repos/service-a/.github/skills/contract-fixtures-a/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Contract fixtures',
    '    requires_skill_use_record: true',
    '  - id: hr-contract-fixtures-b',
    '    name: contract-fixtures',
    '    status: candidate',
    '    origin:',
    '      kind: repo-local',
    '      repo_id: service-a',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/contract-fixtures-b/SKILL.md',
    '    path: workspaces/demo/repos/service-a/.github/skills/contract-fixtures-b/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Contract fixtures',
    '    requires_skill_use_record: true',
  ].join('\n'));

  const skillUse = resolveSkill(root, ['-RepoId', 'service-a', '-Path', 'tests/ContractTests.cs', '-Task', 'contract fixtures']);
  assert.equal(skillUse.status, 'needs_disambiguation');
  assert.deepEqual(skillUse.candidates.sort(), ['hr-contract-fixtures-a', 'hr-contract-fixtures-b']);
});

test('promote-skill projects candidate into meta-root hr skill and updates registry', () => {
  const root = seedRegistry([
    '  - id: hr-payment-contract-fixtures',
    '    name: payment-contract-fixtures',
    '    status: candidate',
    '    origin:',
    '      kind: repo-local',
    '      workspace_id: demo',
    '      repo_id: service-a',
    '      source_path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    path: workspaces/demo/repos/service-a/.github/skills/payment-contract-fixtures/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos:',
    '        - service-a',
    '      paths:',
    '        - tests/*',
    '    confidence: medium',
    '    description: Build PaymentRequest contract fixtures',
    '    requires_skill_use_record: true',
  ].join('\n'));

  writeFile(path.join(root, 'workspaces', 'demo', 'repos', 'service-a', '.github', 'skills', 'payment-contract-fixtures', 'SKILL.md'), [
    '---',
    'name: payment-contract-fixtures',
    'managed-by: helix-runtime',
    'description: Build PaymentRequest contract fixtures',
    'argument-hint: "Scenario"',
    'user-invocable: true',
    '---',
    '',
    '# Payment Contract Fixtures',
    '',
  ].join('\n'));

  const result = runPowerShellFile(PROMOTE_SCRIPT, ['-TargetRoot', root, '-SkillId', 'hr-payment-contract-fixtures'], HELIX_ROOT);
  assert.equal(
    result.status,
    0,
    `promote-skill failed via ${result.command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`
  );

  const promotion = JSON.parse(result.stdout);
  assert.equal(promotion.promoted_skill, 'hr-payment-contract-fixtures');
  assert.ok(fs.existsSync(path.join(root, '.github', 'skills', 'hr-payment-contract-fixtures', 'SKILL.md')));

  const projectedSkill = fs.readFileSync(path.join(root, '.github', 'skills', 'hr-payment-contract-fixtures', 'SKILL.md'), 'utf8');
  assert.match(projectedSkill, /^name: hr-payment-contract-fixtures/m);

  const index = fs.readFileSync(path.join(root, '.helix', 'skills', 'index.yml'), 'utf8');
  assert.match(index, /status: projected/);
  assert.match(index, /projected_path: \.github\/skills\/hr-payment-contract-fixtures\/SKILL\.md/);

  const skillUse = resolveSkill(root, ['-RepoId', 'service-a', '-Path', 'tests/ContractTests.cs', '-Task', 'payment contract fixtures']);
  assert.equal(skillUse.selected_skill, 'hr-payment-contract-fixtures');
  assert.equal(skillUse.status, 'projected');
});

test('promote-skill rejects hc core skills', () => {
  const root = seedRegistry([
    '  - id: hc-workspace-sync',
    '    name: hc-workspace-sync',
    '    status: core',
    '    origin:',
    '      kind: helix-core',
    '      source_path: .github/skills/hc-workspace-sync/SKILL.md',
    '    path: .github/skills/hc-workspace-sync/SKILL.md',
    '    projected_path: null',
    '    scope:',
    '      repos: []',
    '      paths: []',
    '    confidence: high',
    '    description: Sync a Helix workspace',
    '    requires_skill_use_record: true',
  ].join('\n'));

  writeFile(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md'), [
    '---',
    'name: hc-workspace-sync',
    'managed-by: helix-core',
    'description: Sync a Helix workspace',
    'argument-hint: "Workspace name"',
    'user-invocable: true',
    '---',
    '',
    '# Workspace Sync',
    '',
  ].join('\n'));

  const result = runPowerShellFile(PROMOTE_SCRIPT, ['-TargetRoot', root, '-SkillId', 'hc-workspace-sync'], HELIX_ROOT);
  assert.notEqual(result.status, 0, 'core skills should not be projected by promote-skill');
  assert.match(result.stderr, /Helix core skill/);
});
