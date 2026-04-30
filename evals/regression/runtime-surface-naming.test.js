// Locks the Helix Core / Helix Runtime naming convention for runtime-facing files.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');

const CORE_AGENT_NAMES = [
  'architect',
  'decomposer',
  'distiller',
  'explorer',
  'helix',
  'implementer',
  'jam',
  'planner',
  'resume',
  'reviewer',
  'scribe',
  'setup',
  'tdd-red',
  'ui-tester',
];

const CORE_SKILL_NAMES = [
  'build-graph',
  'curate-context',
  'maker',
  'onboard',
  'playwright-cli',
  'refactor',
  'review-delta',
  'review-pr',
  'skill-router',
  'skill-synth',
  'task-board',
  'tdd-cycle',
  'vertical-slice-verifier',
  'workspace-sync',
];

const CORE_PROMPT_NAMES = [
  'distill',
  'jam',
  'label-session',
  'skill-audit',
  'skill-graveyard',
  'surprise',
  'task-breakdown',
  'tech-design',
];

function readFile(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function listFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(fullPath);
    return [fullPath];
  });
}

function frontmatterName(markdown) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---/.exec(markdown);
  assert.ok(match, 'runtime file must start with YAML frontmatter');
  const nameMatch = /^name:\s*(.+?)\s*$/m.exec(match[1]);
  assert.ok(nameMatch, 'runtime frontmatter must include name');
  return nameMatch[1].replace(/^['"]|['"]$/g, '');
}

test('core agents are physically hc-prefixed and frontmatter names match', () => {
  const agentsDir = path.join(HELIX_ROOT, '.github', 'agents');
  const actual = fs.readdirSync(agentsDir).filter((name) => name.endsWith('.agent.md')).sort();
  const expected = CORE_AGENT_NAMES.map((name) => `hc-${name}.agent.md`).sort();
  assert.deepEqual(actual, expected);

  for (const fileName of actual) {
    const baseName = fileName.replace(/\.agent\.md$/, '');
    assert.equal(frontmatterName(readFile(path.join(agentsDir, fileName))), baseName);
  }
});

test('core skills are physically hc-prefixed and frontmatter names match', () => {
  const skillsDir = path.join(HELIX_ROOT, '.github', 'skills');
  const actual = fs.readdirSync(skillsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  const expected = CORE_SKILL_NAMES.map((name) => `hc-${name}`).sort();
  assert.deepEqual(actual, expected);

  for (const dirName of actual) {
    const skillPath = path.join(skillsDir, dirName, 'SKILL.md');
    assert.ok(fs.existsSync(skillPath), `${dirName} is missing SKILL.md`);
    assert.equal(frontmatterName(readFile(skillPath)), dirName);
  }
});

test('core prompts are physically hc-prefixed and frontmatter names match', () => {
  const promptsDir = path.join(HELIX_ROOT, '.github', 'prompts');
  const actual = fs.readdirSync(promptsDir)
    .filter((name) => name.endsWith('.prompt.md'))
    .sort();
  const expected = CORE_PROMPT_NAMES.map((name) => `hc-${name}.prompt.md`).sort();
  assert.deepEqual(actual, expected);

  for (const fileName of actual) {
    const baseName = fileName.replace(/\.prompt\.md$/, '');
    assert.equal(frontmatterName(readFile(path.join(promptsDir, fileName))), baseName);
  }
});

test('source runtime references use HC command and agent names', () => {
  const roots = ['.github', 'docs', 'templates', 'scripts', 'evals', 'workspaces', '.helix'];
  const files = roots
    .map((root) => path.join(HELIX_ROOT, root))
    .filter((root) => fs.existsSync(root))
    .flatMap(listFiles)
    .filter((filePath) => !filePath.includes(`${path.sep}.git${path.sep}`));

  const agentPattern = new RegExp(`@(?!hc-)(${CORE_AGENT_NAMES.join('|')})\\b`);
  const handoffPattern = new RegExp(`^\\s*agent:\\s*(?!hc-)(${CORE_AGENT_NAMES.join('|')})\\b`, 'm');
  const slashPattern = new RegExp(`(?<![A-Za-z0-9._-])/(?!hc-)(${[...CORE_SKILL_NAMES, ...CORE_PROMPT_NAMES].join('|')})(?![A-Za-z0-9._/-])`);
  const staleCorePrefixPattern = new RegExp(`(?<![A-Za-z0-9])${'h'}${'e'}-[a-z0-9]`, 'i');

  for (const filePath of files) {
    const text = readFile(filePath);
    assert.doesNotMatch(text, staleCorePrefixPattern, `${filePath} contains a stale core prefix`);
    assert.doesNotMatch(text, agentPattern, `${filePath} contains an unprefixed agent invocation`);
    assert.doesNotMatch(text, handoffPattern, `${filePath} contains an unprefixed handoff agent`);
    assert.doesNotMatch(text, slashPattern, `${filePath} contains an unprefixed slash command reference`);
  }
});
