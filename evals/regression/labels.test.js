// Asserts the Layer 2 label-file schema in helix/docs/label-schema.md.
// Validator is colocated here because today there is no other consumer; if a
// label-loading script lands later, lift validateLabel into a shared module.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const RUNTIME = path.resolve(__dirname, '..', '..', '.github', 'hooks', 'scripts', 'helix-runtime.js');
const { parseSimpleYaml } = require(RUNTIME);

const ALLOWED_KEYS = new Set(['correctness', 'rework', 'notes']);
const CORRECTNESS = new Set(['match', 'partial', 'wrong']);
const REWORK = new Set(['none', 'minor', 'major']);

function validateLabel(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    return { ok: false, error: 'not_an_object' };
  }
  for (const key of Object.keys(obj)) {
    if (!ALLOWED_KEYS.has(key)) return { ok: false, error: `unknown_field:${key}` };
  }
  for (const key of ALLOWED_KEYS) {
    if (!(key in obj)) return { ok: false, error: `missing_field:${key}` };
  }
  if (!CORRECTNESS.has(obj.correctness)) return { ok: false, error: 'bad_correctness' };
  if (!REWORK.has(obj.rework)) return { ok: false, error: 'bad_rework' };
  if (typeof obj.notes !== 'string') return { ok: false, error: 'bad_notes_type' };
  if (obj.notes.includes('\n')) return { ok: false, error: 'notes_must_be_single_line' };
  return { ok: true };
}

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'helix-label-'));
}

test('validateLabel: well-formed accepted', () => {
  assert.deepEqual(
    validateLabel({ correctness: 'match', rework: 'none', notes: '' }),
    { ok: true }
  );
});

test('validateLabel: each correctness enum accepted', () => {
  for (const c of ['match', 'partial', 'wrong']) {
    assert.equal(validateLabel({ correctness: c, rework: 'none', notes: '' }).ok, true);
  }
});

test('validateLabel: each rework enum accepted', () => {
  for (const r of ['none', 'minor', 'major']) {
    assert.equal(validateLabel({ correctness: 'match', rework: r, notes: '' }).ok, true);
  }
});

test('validateLabel: bad correctness enum rejected', () => {
  const out = validateLabel({ correctness: 'ok', rework: 'none', notes: '' });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'bad_correctness');
});

test('validateLabel: bad rework enum rejected', () => {
  const out = validateLabel({ correctness: 'match', rework: 'medium', notes: '' });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'bad_rework');
});

test('validateLabel: missing notes rejected', () => {
  const out = validateLabel({ correctness: 'match', rework: 'none' });
  assert.equal(out.ok, false);
  assert.match(out.error, /^missing_field:notes$/);
});

test('validateLabel: missing correctness rejected', () => {
  const out = validateLabel({ rework: 'none', notes: '' });
  assert.equal(out.ok, false);
  assert.match(out.error, /^missing_field:correctness$/);
});

test('validateLabel: missing rework rejected', () => {
  const out = validateLabel({ correctness: 'match', notes: '' });
  assert.equal(out.ok, false);
  assert.match(out.error, /^missing_field:rework$/);
});

test('validateLabel: extra field rejected (closed schema)', () => {
  const out = validateLabel({ correctness: 'match', rework: 'none', notes: '', reviewer: 'sam' });
  assert.equal(out.ok, false);
  assert.match(out.error, /^unknown_field:reviewer$/);
});

test('validateLabel: notes must be a string', () => {
  const out = validateLabel({ correctness: 'match', rework: 'none', notes: 42 });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'bad_notes_type');
});

test('validateLabel: multi-line notes rejected', () => {
  const out = validateLabel({ correctness: 'match', rework: 'none', notes: 'line1\nline2' });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'notes_must_be_single_line');
});

test('validateLabel: non-object inputs rejected', () => {
  assert.equal(validateLabel(null).ok, false);
  assert.equal(validateLabel(undefined).ok, false);
  assert.equal(validateLabel('string').ok, false);
  assert.equal(validateLabel([]).ok, false);
});

test('roundtrip: well-formed YAML fixture parses and validates', () => {
  const dir = tmpDir();
  const labelPath = path.join(dir, 'session-abc.label.yml');
  fs.writeFileSync(
    labelPath,
    'correctness: partial\nrework: minor\nnotes: "Architect missed auth-coupling on orders endpoint"\n',
    'utf8'
  );
  const parsed = parseSimpleYaml(fs.readFileSync(labelPath, 'utf8'));
  assert.deepEqual(validateLabel(parsed), { ok: true });
  assert.equal(parsed.correctness, 'partial');
  assert.equal(parsed.rework, 'minor');
  assert.equal(parsed.notes, 'Architect missed auth-coupling on orders endpoint');
});

test('roundtrip: extra-field YAML fixture parses and is rejected', () => {
  const dir = tmpDir();
  const labelPath = path.join(dir, 'session-xyz.label.yml');
  fs.writeFileSync(
    labelPath,
    'correctness: match\nrework: none\nnotes: ""\nreviewer: sam\n',
    'utf8'
  );
  const parsed = parseSimpleYaml(fs.readFileSync(labelPath, 'utf8'));
  const out = validateLabel(parsed);
  assert.equal(out.ok, false);
  assert.match(out.error, /^unknown_field:reviewer$/);
});

test('roundtrip: out-of-enum YAML fixture parses and is rejected', () => {
  const dir = tmpDir();
  const labelPath = path.join(dir, 'session-bad.label.yml');
  fs.writeFileSync(
    labelPath,
    'correctness: ok\nrework: none\nnotes: ""\n',
    'utf8'
  );
  const parsed = parseSimpleYaml(fs.readFileSync(labelPath, 'utf8'));
  assert.equal(validateLabel(parsed).error, 'bad_correctness');
});
