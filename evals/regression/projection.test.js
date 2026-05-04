// Exercises the workspace-skill projection mechanism in setup-workspace.ps1
// (Helix.Tools.psm1::Publish-HelixWorkspaceSkill, Get-HelixWorkspaceSkillSource).

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

function seedMetaRepo({
  workspaceId = 'demo',
  repos = [], // [{ id, skills: [{ name, frontmatterExtra?, body? }] }]
} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-projection-'));

  writeFile(path.join(root, '.helix', 'context-providers.yml'), [
    'providers:',
    '  code_review_graph:',
    '    mode: off',
    '',
  ].join('\n'));

  const repoLines = ['schema_version: 1', 'defaults:', '  default_branch: main', 'repos:'];
  const workspaceRepoLines = [];
  for (const r of repos) {
    repoLines.push(
      `  - id: ${r.id}`,
      `    remote: https://github.com/example-org/${r.id}.git`,
      `    local_path: workspaces/${workspaceId}/repos/${r.id}`,
      `    default_branch: main`,
    );
    workspaceRepoLines.push(`  - repo_id: ${r.id}`, `    role: primary`, `    branch: main`);
  }
  writeFile(path.join(root, 'helix-repos.yml'), repoLines.concat(['']).join('\n'));

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
    ...workspaceRepoLines,
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

  // baseline meta-root core skill so the index isn't empty
  writeFile(path.join(root, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md'), [
    '---', 'name: hc-workspace-sync', 'managed-by: helix-core',
    'description: Sync a Helix workspace', 'argument-hint: "Workspace name"',
    'user-invocable: true', '---', '', '# Workspace Sync', '',
  ].join('\n'));

  // also a baseline hr-* projection that must survive switches
  writeFile(path.join(root, '.github', 'skills', 'hr-baseline', 'SKILL.md'), [
    '---', 'name: hr-baseline', 'managed-by: helix-runtime',
    'description: Pre-existing helix-reusable skill', 'user-invocable: true', '---', '',
    '# HR Baseline', '',
  ].join('\n'));

  for (const r of repos) {
    const repoRoot = path.join(root, 'workspaces', workspaceId, 'repos', r.id);
    writeFile(path.join(repoRoot, 'AGENTS.md'), `# ${r.id}\n`);
    fs.mkdirSync(path.join(repoRoot, 'tests'), { recursive: true });
    for (const s of r.skills || []) {
      const fmLines = [
        '---',
        `name: ${s.name}`,
        'managed-by: helix-runtime',
        `description: ${s.description || 'Test skill ' + s.name}`,
      ];
      if (s.frontmatterExtra) fmLines.push(...s.frontmatterExtra);
      fmLines.push('---', '');
      writeFile(path.join(repoRoot, '.github', 'skills', s.name, 'SKILL.md'),
        fmLines.concat([s.body || `# ${s.name}\n`]).join('\n'));
    }
  }

  return root;
}

function runSetup(root, workspaceId = 'demo') {
  return runPowerShellFile(SETUP_SCRIPT, ['-Workspace', workspaceId, '-TargetRoot', root], HELIX_ROOT);
}

test('projection-basic: two repos with one skill each are projected with repo-prefixed names', () => {
  const root = seedMetaRepo({
    repos: [
      { id: 'service-a', skills: [{ name: 'code-review' }] },
      { id: 'service-b', skills: [{ name: 'code-review' }] },
    ],
  });
  const r = runSetup(root);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  const a = path.join(root, '.github', 'skills', 'service-a-code-review', 'SKILL.md');
  const b = path.join(root, '.github', 'skills', 'service-b-code-review', 'SKILL.md');
  assert.ok(fs.existsSync(a), 'service-a projection missing');
  assert.ok(fs.existsSync(b), 'service-b projection missing');

  const aContent = fs.readFileSync(a, 'utf8');
  assert.match(aContent, /name: service-a-code-review/);
  assert.match(aContent, /from_repo: service-a/);
  assert.match(aContent, /from_name: code-review/);

  const bContent = fs.readFileSync(b, 'utf8');
  assert.match(bContent, /name: service-b-code-review/);
  assert.match(bContent, /from_repo: service-b/);
});

test('projection-skip: source skill with `projection: never` is not projected', () => {
  const root = seedMetaRepo({
    repos: [{
      id: 'service-a',
      skills: [
        { name: 'normal-skill' },
        { name: 'local-only-skill', frontmatterExtra: ['projection: never'] },
      ],
    }],
  });
  const r = runSetup(root);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  assert.ok(fs.existsSync(path.join(root, '.github', 'skills', 'service-a-normal-skill', 'SKILL.md')));
  assert.equal(
    fs.existsSync(path.join(root, '.github', 'skills', 'service-a-local-only-skill')),
    false,
    'local-only-skill should have been skipped'
  );
});

test('projection-collision: two repos that would project to the same name fail hard', () => {
  // service-a and service-a-extra both define a skill named "shared"
  // → would project to service-a-shared and service-a-extra-shared (no collision)
  // To force a collision, we use repos with the same short slug. ConvertTo-HelixRepoShortSlug
  // collapses non-alphanumerics, so "team_alpha" and "team-alpha" both slug to "team-alpha".
  const root = seedMetaRepo({
    repos: [
      { id: 'team-alpha', skills: [{ name: 'shared' }] },
      { id: 'team_alpha', skills: [{ name: 'shared' }] },
    ],
  });
  const r = runSetup(root);
  assert.notEqual(r.status, 0, 'expected setup to fail with a collision error');
  const combined = `${r.stdout}\n${r.stderr}`;
  assert.match(combined, /collision/i, 'expected a collision error message');
});

test('projection-readonly: projected SKILL.md is read-only on disk', () => {
  const root = seedMetaRepo({
    repos: [{ id: 'service-a', skills: [{ name: 'code-review' }] }],
  });
  const r = runSetup(root);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  const projected = path.join(root, '.github', 'skills', 'service-a-code-review', 'SKILL.md');
  const stat = fs.statSync(projected);
  if (process.platform === 'win32') {
    // On Windows, read-only is a file attribute; Node exposes it via mode bits.
    // The simplest cross-runtime check: try to open for write and assert it fails.
    let writeFailed = false;
    try {
      fs.writeFileSync(projected, 'tampered');
    } catch (e) {
      writeFailed = true;
    }
    assert.ok(writeFailed, 'projected file should not be writable');
  } else {
    // POSIX: owner write bit cleared.
    assert.equal(stat.mode & 0o200, 0, 'projected file should not have owner-write bit');
  }
});

test('projection-frontmatter: projected SKILL.md has provenance fields', () => {
  const root = seedMetaRepo({
    repos: [{ id: 'service-a', skills: [{ name: 'code-review' }] }],
  });
  const r = runSetup(root);
  assert.equal(r.status, 0, `setup failed:\n${r.stdout}\n${r.stderr}`);

  const projected = path.join(root, '.github', 'skills', 'service-a-code-review', 'SKILL.md');
  const text = fs.readFileSync(projected, 'utf8');
  assert.match(text, /^projection:$/m, 'projection block missing');
  assert.match(text, /from_repo: service-a/);
  assert.match(text, /from_path: .github\/skills\/code-review/);
  assert.match(text, /from_name: code-review/);
  assert.match(text, /projected_at: "?20\d\d-/, 'projected_at should be an ISO date');
  assert.match(text, /checksum: "?sha256:[0-9a-f]{64}"?/, 'sha256 checksum missing');
});
