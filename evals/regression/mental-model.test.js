// Asserts the Track T4 mental-model contract:
//   1. helix/.github/prompts/surprise.prompt.md exists and conforms to the
//      ≤30-line verbosity discipline shared with other Helix prompts.
//   2. helix/templates/mental-model.md.template carries the six required
//      sections (Domain Glossary, Flag Inventory, Coupling Map, Behavior
//      Conditions, State Diagrams, Surprise Log) in the documented order.
//   3. The append behaviour described in helix/docs/mental-model-architecture.md
//      can be exercised in pure JS against a tmp workspace: appending a dated
//      surprise subsection under `## Surprise Log` only grows that section,
//      leaves earlier sections byte-identical, and preserves the heading order.
//
// Validators / helpers are colocated. Lift them into a shared module if a real
// consumer (e.g. a /surprise script implementation) ever lands.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const TEMPLATE_PATH = path.join(REPO_ROOT, 'helix', 'templates', 'mental-model.md.template');
const PROMPT_PATH = path.join(REPO_ROOT, 'helix', '.github', 'prompts', 'surprise.prompt.md');

const REQUIRED_SECTIONS = [
  'Domain Glossary',
  'Flag Inventory',
  'Coupling Map',
  'Behavior Conditions',
  'State Diagrams',
  'Surprise Log',
];

const PROMPT_LINE_CAP = 30;

function readFile(p) {
  return fs.readFileSync(p, 'utf8');
}

function topLevelSections(markdown) {
  // Returns [{ name, start, end }] for every `## Heading` block.
  // start/end are line indices (end exclusive). Last section runs to EOF.
  const lines = markdown.split(/\r?\n/);
  const headings = [];
  for (let i = 0; i < lines.length; i++) {
    const m = /^##\s+(.+?)\s*$/.exec(lines[i]);
    if (m && !lines[i].startsWith('### ')) {
      headings.push({ name: m[1], lineIndex: i });
    }
  }
  const sections = [];
  for (let i = 0; i < headings.length; i++) {
    const start = headings[i].lineIndex;
    const end = i + 1 < headings.length ? headings[i + 1].lineIndex : lines.length;
    sections.push({ name: headings[i].name, start, end });
  }
  return { sections, lines };
}

function countH3Subsections(lines, start, end) {
  let n = 0;
  for (let i = start; i < end; i++) {
    if (/^###\s+/.test(lines[i])) n++;
  }
  return n;
}

function appendSurprise(markdown, { date, title, expected, actual, repos }) {
  // Appends a `### {date} — {title}` subsection at the end of the existing
  // `## Surprise Log` section. Does not touch any other section.
  const { sections, lines } = topLevelSections(markdown);
  const log = sections.find((s) => s.name === 'Surprise Log');
  if (!log) throw new Error('mental-model.md missing ## Surprise Log section');

  const block = [
    `### ${date} — ${title}`,
    '',
    `**Expected:** ${expected}`,
    `**Actual:** ${actual}`,
  ];
  if (repos) block.push(`**Repos:** ${repos}`);
  block.push('');

  // Insert at log.end (one past the last line of the Surprise Log section).
  const before = lines.slice(0, log.end);
  const after = lines.slice(log.end);
  return [...before, ...block, ...after].join('\n');
}

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'helix-mental-model-'));
}

test('prompt: surprise.prompt.md exists', () => {
  assert.ok(fs.existsSync(PROMPT_PATH), `missing prompt at ${PROMPT_PATH}`);
});

test('prompt: surprise.prompt.md respects ≤30-line cap', () => {
  const lineCount = readFile(PROMPT_PATH).split(/\r?\n/).filter((_, i, a) => i < a.length - 1 || a[i] !== '').length;
  // Match the discipline used by label-session.prompt.md (29 lines).
  assert.ok(
    lineCount <= PROMPT_LINE_CAP,
    `surprise.prompt.md is ${lineCount} lines, cap is ${PROMPT_LINE_CAP}`
  );
});

test('template: mental-model.md.template exists', () => {
  assert.ok(fs.existsSync(TEMPLATE_PATH), `missing template at ${TEMPLATE_PATH}`);
});

test('template: has the six required sections in the documented order', () => {
  const { sections } = topLevelSections(readFile(TEMPLATE_PATH));
  const names = sections.map((s) => s.name);
  assert.deepEqual(
    names,
    REQUIRED_SECTIONS,
    `expected exactly ${REQUIRED_SECTIONS.join(' / ')}; saw ${names.join(' / ')}`
  );
});

test('append behaviour: surprise entry only grows the Surprise Log section', () => {
  const dir = tmpDir();
  const target = path.join(dir, 'mental-model.md');
  fs.copyFileSync(TEMPLATE_PATH, target);

  const before = readFile(target);
  const beforeParse = topLevelSections(before);
  const beforeLogIdx = beforeParse.sections.findIndex((s) => s.name === 'Surprise Log');
  const beforeLog = beforeParse.sections[beforeLogIdx];
  const beforeLogSubsectionCount = countH3Subsections(beforeParse.lines, beforeLog.start, beforeLog.end);

  const after = appendSurprise(before, {
    date: '2026-04-29',
    title: 'orders-api emits OrderPlaced.v1 but worker subscribes to v0',
    expected: 'Coupling map said both repos handled v1.',
    actual: 'orders-worker still hard-codes v0 in its subscription bootstrap.',
    repos: 'orders-api, orders-worker',
  });
  fs.writeFileSync(target, after, 'utf8');

  const afterParse = topLevelSections(after);

  // (a) all six top-level sections still present, in order.
  assert.deepEqual(
    afterParse.sections.map((s) => s.name),
    REQUIRED_SECTIONS,
    'top-level section order changed after surprise append'
  );

  // (b) only the Surprise Log section's subsection count grew by one.
  for (let i = 0; i < REQUIRED_SECTIONS.length; i++) {
    const beforeSec = beforeParse.sections[i];
    const afterSec = afterParse.sections[i];
    const beforeCount = countH3Subsections(beforeParse.lines, beforeSec.start, beforeSec.end);
    const afterCount = countH3Subsections(afterParse.lines, afterSec.start, afterSec.end);
    if (REQUIRED_SECTIONS[i] === 'Surprise Log') {
      assert.equal(
        afterCount - beforeCount,
        1,
        `Surprise Log h3 count should grow by 1 (was ${beforeCount}, now ${afterCount})`
      );
    } else {
      assert.equal(
        afterCount,
        beforeCount,
        `${REQUIRED_SECTIONS[i]} h3 count should be unchanged (was ${beforeCount}, now ${afterCount})`
      );
    }
  }

  // (c) earlier sections' byte content is unchanged (everything before the
  //     Surprise Log heading must be byte-for-byte identical).
  const surpriseLogStart = afterParse.sections[afterParse.sections.length - 1].start;
  const beforePrefix = beforeParse.lines.slice(0, beforeParse.sections[beforeLogIdx].start).join('\n');
  const afterPrefix = afterParse.lines.slice(0, surpriseLogStart).join('\n');
  assert.equal(afterPrefix, beforePrefix, 'content before ## Surprise Log was modified');

  // (d) the appended block contains the dated heading and structured fields.
  const tail = afterParse.lines.slice(surpriseLogStart).join('\n');
  assert.match(tail, /### 2026-04-29 — orders-api emits OrderPlaced\.v1/);
  assert.match(tail, /\*\*Expected:\*\* Coupling map said both repos handled v1\./);
  assert.match(tail, /\*\*Actual:\*\* orders-worker still hard-codes v0/);
  assert.match(tail, /\*\*Repos:\*\* orders-api, orders-worker/);
});

test('append behaviour: omitting repos drops the Repos line', () => {
  const dir = tmpDir();
  const target = path.join(dir, 'mental-model.md');
  fs.copyFileSync(TEMPLATE_PATH, target);

  const result = appendSurprise(readFile(target), {
    date: '2026-04-29',
    title: 'untyped contract drift',
    expected: 'producer field stayed string',
    actual: 'producer field switched to enum mid-week',
    repos: '',
  });

  assert.match(result, /### 2026-04-29 — untyped contract drift/);
  assert.doesNotMatch(result, /\*\*Repos:\*\*/);
});

test('append behaviour: two surprises in a row both land in Surprise Log', () => {
  const dir = tmpDir();
  const target = path.join(dir, 'mental-model.md');
  fs.copyFileSync(TEMPLATE_PATH, target);

  let body = readFile(target);
  body = appendSurprise(body, { date: '2026-04-29', title: 'first', expected: 'a', actual: 'b', repos: '' });
  body = appendSurprise(body, { date: '2026-04-30', title: 'second', expected: 'c', actual: 'd', repos: '' });

  const { sections, lines } = topLevelSections(body);
  const log = sections.find((s) => s.name === 'Surprise Log');
  const count = countH3Subsections(lines, log.start, log.end);
  assert.equal(count, 2, `expected 2 surprise subsections, got ${count}`);

  // Order preserved: the older entry appears before the newer one in the file.
  const firstIdx = body.indexOf('### 2026-04-29 — first');
  const secondIdx = body.indexOf('### 2026-04-30 — second');
  assert.ok(firstIdx > -1 && secondIdx > firstIdx, 'append order not preserved');
});
