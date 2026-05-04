// Asserts that skill-selection guidance exists at one canonical surface:
// either a "Choosing a skill" section in helix/AGENTS.md, or
// helix/docs/skill-selection.md linked from helix/AGENTS.md.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const HELIX_ROOT = path.join(WORKSPACE_ROOT, 'helix');
const AGENTS_MD = path.join(HELIX_ROOT, 'AGENTS.md');
const SELECTION_DOC = path.join(HELIX_ROOT, 'docs', 'skill-selection.md');

test('skill-selection guidance exists in AGENTS.md or in a linked skill-selection.md', () => {
  assert.ok(fs.existsSync(AGENTS_MD), 'helix/AGENTS.md must exist');
  const agentsBody = fs.readFileSync(AGENTS_MD, 'utf8');

  const hasInlineSection = /^##\s+Choosing a skill\s*$/m.test(agentsBody);

  if (hasInlineSection) {
    return;
  }

  assert.ok(
    fs.existsSync(SELECTION_DOC),
    'expected either a "Choosing a skill" section in helix/AGENTS.md or helix/docs/skill-selection.md to exist'
  );

  const linkPattern = /skill-selection\.md/;
  assert.ok(
    linkPattern.test(agentsBody),
    'helix/docs/skill-selection.md exists but is not linked from helix/AGENTS.md'
  );
});
