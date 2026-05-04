// Verifies the .helix/skills/index.yml v2 schema and v1 backward-compat read path
// (Step 6 of skill-projection-and-simplification-plan.md).

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const TOOLS_MODULE = path.join(HELIX_ROOT, 'scripts', 'Helix.Tools.psm1');

function runPowerShell(script, cwd) {
  const candidates = process.platform === 'win32' ? ['pwsh.exe', 'powershell.exe'] : ['pwsh'];
  for (const command of candidates) {
    const result = spawnSync(
      command,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      { cwd, encoding: 'utf8' }
    );
    if (result.error && result.error.code === 'ENOENT') continue;
    return { command, ...result };
  }
  throw new Error('No PowerShell executable found.');
}

test('index v1 with routing/host_visible loads via Read-HelixSkillIndex and upgrades to v2 in memory', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-index-v1-'));
  const indexPath = path.join(tmp, 'index.yml');
  fs.writeFileSync(indexPath, [
    'schema_version: 1',
    'updated_at: "2026-01-01T00:00:00Z"',
    'active_workspace: legacy',
    'skills:',
    '  - id: hc-architect',
    '    name: hc-architect',
    '    status: core',
    '    access:',
    '      host_visible: true',
    '      source: meta-root-skill',
    '    routing:',
    '      use_mode: invoke',
    '    path: .github/skills/hc-architect/SKILL.md',
    '',
  ].join('\n'), 'utf8');

  const script = [
    `Import-Module "${TOOLS_MODULE.replace(/\\/g, '/')}" -Force`,
    `$idx = Read-HelixSkillIndex -Path "${indexPath.replace(/\\/g, '/')}"`,
    `Write-Host "version=$($idx.schema_version)"`,
    `Write-Host "skills_count=$($idx.skills.Count)"`,
    `$first = $idx.skills[0]`,
    `Write-Host "id=$($first.id)"`,
    `Write-Host "has_routing=$($first.Contains('routing'))"`,
    `Write-Host "has_access_host_visible=$($first.access.Contains('host_visible'))"`,
    `Write-Host "access_source=$($first.access.source)"`,
  ].join('; ');

  const r = runPowerShell(script, HELIX_ROOT);
  assert.equal(r.status, 0, `pwsh failed:\n${r.stdout}\n${r.stderr}`);
  assert.match(r.stdout, /version=2/);
  assert.match(r.stdout, /skills_count=1/);
  assert.match(r.stdout, /id=hc-architect/);
  assert.match(r.stdout, /has_routing=False/, 'routing field should be stripped on upgrade');
  assert.match(r.stdout, /has_access_host_visible=False/, 'access.host_visible should be stripped on upgrade');
  assert.match(r.stdout, /access_source=meta-root-skill/);
});

test('index v2 written by Write-HelixSkillIndex omits routing and access.host_visible', () => {
  // Write-HelixSkillIndex needs a meta-root with at least .github/skills/* to scan.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-index-v2-'));
  fs.mkdirSync(path.join(tmp, '.github', 'skills', 'hc-test'), { recursive: true });
  fs.writeFileSync(path.join(tmp, '.github', 'skills', 'hc-test', 'SKILL.md'), [
    '---', 'name: hc-test', 'managed-by: helix-core',
    'description: test', '---', '', '# hc-test\n',
  ].join('\n'), 'utf8');

  const script = [
    `Import-Module "${TOOLS_MODULE.replace(/\\/g, '/')}" -Force`,
    `Write-HelixSkillIndex -TargetRoot "${tmp.replace(/\\/g, '/')}" -WorkspaceName test | Out-Null`,
  ].join('; ');
  const r = runPowerShell(script, HELIX_ROOT);
  assert.equal(r.status, 0, `pwsh failed:\n${r.stdout}\n${r.stderr}`);

  const indexPath = path.join(tmp, '.helix', 'skills', 'index.yml');
  assert.ok(fs.existsSync(indexPath));
  const text = fs.readFileSync(indexPath, 'utf8');
  assert.match(text, /^schema_version: 2$/m);
  assert.doesNotMatch(text, /routing:/, 'routing field should not be emitted');
  assert.doesNotMatch(text, /host_visible:/, 'access.host_visible should not be emitted');
  assert.match(text, /^\s+access:\r?\n\s+source: meta-root-skill\s*$/m);
});
