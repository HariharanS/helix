// Asserts that helix/.github/prompts/hc-distill.prompt.md is a thin wrapper:
// it points at the canonical owner doc (distillation-architecture.md) and does
// not duplicate the candidate schema or promotion-gate formula that live in
// that doc.
//
// See helix/docs/skill-projection-and-simplification-plan.md Step 7.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const HELIX_ROOT = path.resolve(__dirname, '..', '..');
const PROMPT = path.join(HELIX_ROOT, '.github', 'prompts', 'hc-distill.prompt.md');
const DOC = path.join(HELIX_ROOT, 'docs', 'distillation-architecture.md');

// Schema-shaped tokens that live in distillation-architecture.md and must NOT
// be duplicated in the prompt. If any new token is added to the doc's schemas
// and the prompt copies it, this test should catch it — extend the list rather
// than weakening the check.
const SCHEMA_TOKENS = [
  'held_out_replay',       // candidate frontmatter
  'quarterly_promotions',  // promotion-gate formula
  'last_evidence',         // candidate frontmatter
  'ELIGIBLE-BUT-CAPPED',   // gate status enum
  "Don't re-suggest if",   // graveyard fingerprint header
];

test('hc-distill.prompt.md exists and links to distillation-architecture.md', () => {
  assert.ok(fs.existsSync(PROMPT), 'helix/.github/prompts/hc-distill.prompt.md must exist');
  assert.ok(fs.existsSync(DOC), 'helix/docs/distillation-architecture.md must exist');

  const body = fs.readFileSync(PROMPT, 'utf8');
  assert.match(
    body,
    /distillation-architecture\.md/,
    'prompt must link to distillation-architecture.md as the canonical owner of schemas/gates/triggers'
  );
});

test('hc-distill.prompt.md does not duplicate candidate-schema or gate tokens from the doc', () => {
  const body = fs.readFileSync(PROMPT, 'utf8');
  for (const token of SCHEMA_TOKENS) {
    assert.ok(
      !body.includes(token),
      `hc-distill.prompt.md must not duplicate "${token}" — it belongs in distillation-architecture.md`
    );
  }
});

test('hc-distill.prompt.md does not embed a verbatim schema fenced-code block', () => {
  const body = fs.readFileSync(PROMPT, 'utf8');
  // Find body fences (skip the leading frontmatter delimited by --- ... ---).
  const afterFrontmatter = body.replace(/^---[\s\S]*?\n---\s*\n/, '');
  const fenceRe = /```[a-zA-Z0-9_-]*\n([\s\S]*?)```/g;
  let match;
  while ((match = fenceRe.exec(afterFrontmatter)) !== null) {
    const inner = match[1];
    // A schema block characteristically contains multiple `field:` lines and
    // schema-shaped placeholders. Reject any fenced block that looks like one.
    const fieldLineCount = (inner.match(/^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*:/gm) || []).length;
    const hasPlaceholder = /<[^>]+>/.test(inner) || /\{[^}]+\}/.test(inner);
    assert.ok(
      !(fieldLineCount >= 3 && hasPlaceholder),
      `hc-distill.prompt.md contains a fenced block that looks like a schema duplication:\n${match[0]}`
    );
  }
});
