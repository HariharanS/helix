// Asserts that hc-skill-router is no longer referenced as a runtime dispatcher
// in agent or prompt files. Plan/changelog docs are explicitly out of scope.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const NEEDLE = 'hc-skill-router';

function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(fullPath);
    return [fullPath];
  });
}

function findReferences(dir) {
  const offenders = [];
  for (const filePath of listFiles(dir)) {
    const contents = fs.readFileSync(filePath, 'utf8');
    if (contents.includes(NEEDLE)) {
      offenders.push(path.relative(WORKSPACE_ROOT, filePath));
    }
  }
  return offenders;
}

test('no agent file references hc-skill-router', () => {
  const offenders = findReferences(path.join(HELIX_ROOT, '.github', 'agents'));
  assert.deepEqual(
    offenders,
    [],
    `agent files must not reference hc-skill-router; found in:\n${offenders.join('\n')}`
  );
});

test('no prompt file references hc-skill-router', () => {
  const offenders = findReferences(path.join(HELIX_ROOT, '.github', 'prompts'));
  assert.deepEqual(
    offenders,
    [],
    `prompt files must not reference hc-skill-router; found in:\n${offenders.join('\n')}`
  );
});

test('hc-skill-router skill folder no longer exists', () => {
  const skillPath = path.join(HELIX_ROOT, '.github', 'skills', 'hc-skill-router');
  assert.equal(
    fs.existsSync(skillPath),
    false,
    'hc-skill-router skill folder must be deleted'
  );
});
