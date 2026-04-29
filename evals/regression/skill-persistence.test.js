// Validates the schemas in helix/docs/distillation-architecture.md for the
// .helix/skills/{candidates,graveyard}/ files and usage.jsonl records.
// Validators are colocated; lift into a shared module when a real consumer
// (audit script, promotion-gate evaluator) ships.

const test = require('node:test');
const assert = require('node:assert/strict');

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;

const CANDIDATE_STATUS = new Set(['candidate', 'promoted', 'graveyarded']);
const REPLAY = new Set(['PASS', 'PARTIAL', 'FAIL', 'UNTESTED']);
const CONFIDENCE = new Set(['low', 'medium', 'high']);
const DESTINATION = new Set(['repo', 'workspace/meta', 'helix-core', 'personal']);
const GRAVEYARD_REASON = new Set([
  'too-bespoke', 'covered-elsewhere', 'low-frequency', 'replay-fails', 'operator-rejected',
]);
const PRIOR_STATUS = new Set(['candidate', 'promoted']);

function validateCandidateFrontmatter(fm) {
  const errors = [];
  if (typeof fm.id !== 'string' || !KEBAB.test(fm.id)) errors.push('id must be kebab-case');
  if (!CANDIDATE_STATUS.has(fm.status)) errors.push(`status must be one of ${[...CANDIDATE_STATUS]}`);
  if (typeof fm.created !== 'string' || !ISO_DATE.test(fm.created)) errors.push('created must be YYYY-MM-DD');
  if (typeof fm.last_evidence !== 'string' || !ISO_DATE.test(fm.last_evidence)) {
    errors.push('last_evidence must be YYYY-MM-DD');
  }
  if (!Number.isInteger(fm.occurrences) || fm.occurrences < 0) errors.push('occurrences must be a non-negative integer');
  if (!Array.isArray(fm.features) || fm.features.some(f => typeof f !== 'string')) {
    errors.push('features must be an array of strings');
  }
  if (fm.occurrences > 0 && fm.features.length === 0) {
    errors.push('features cannot be empty when occurrences > 0');
  }
  if (!REPLAY.has(fm.held_out_replay)) errors.push(`held_out_replay must be one of ${[...REPLAY]}`);
  if (!CONFIDENCE.has(fm.confidence)) errors.push(`confidence must be one of ${[...CONFIDENCE]}`);
  if (!DESTINATION.has(fm.destination)) errors.push(`destination must be one of ${[...DESTINATION]}`);
  return errors;
}

function validateGraveyardFrontmatter(fm) {
  const errors = [];
  if (typeof fm.id !== 'string' || !KEBAB.test(fm.id)) errors.push('id must be kebab-case');
  if (typeof fm.graveyarded !== 'string' || !ISO_DATE.test(fm.graveyarded)) {
    errors.push('graveyarded must be YYYY-MM-DD');
  }
  if (!GRAVEYARD_REASON.has(fm.reason)) errors.push(`reason must be one of ${[...GRAVEYARD_REASON]}`);
  if (!PRIOR_STATUS.has(fm.last_status_before)) {
    errors.push(`last_status_before must be one of ${[...PRIOR_STATUS]}`);
  }
  return errors;
}

function validateUsageRecord(rec) {
  const errors = [];
  if (typeof rec.ts !== 'string' || !ISO_TIMESTAMP.test(rec.ts)) errors.push('ts must be ISO-8601');
  if (typeof rec.skill_id !== 'string' || !KEBAB.test(rec.skill_id)) errors.push('skill_id must be kebab-case');
  if (typeof rec.session_id !== 'string' || rec.session_id.length === 0) errors.push('session_id must be non-empty');
  if (typeof rec.workspace !== 'string' || rec.workspace.length === 0) errors.push('workspace must be non-empty');
  if (rec.edit_distance !== null && (typeof rec.edit_distance !== 'number' || rec.edit_distance < 0)) {
    errors.push('edit_distance must be null or a non-negative number');
  }
  return errors;
}

const validCandidate = {
  id: 'csharp-record-with-validators',
  status: 'candidate',
  created: '2026-04-28',
  last_evidence: '2026-04-29',
  occurrences: 4,
  features: ['feature-orders-events', 'feature-billing-rewrite'],
  held_out_replay: 'PASS',
  confidence: 'medium',
  destination: 'workspace/meta',
};

const validGraveyard = {
  id: 'csharp-record-with-validators',
  graveyarded: '2026-05-15',
  reason: 'too-bespoke',
  last_status_before: 'candidate',
};

const validUsage = {
  ts: '2026-05-01T10:14:22.000Z',
  skill_id: 'csharp-record-with-validators',
  session_id: 'abc123',
  workspace: 'feature-orders-events',
  edit_distance: null,
};

test('candidate: example from distillation-architecture.md validates', () => {
  assert.deepEqual(validateCandidateFrontmatter(validCandidate), []);
});

test('candidate: rejects non-kebab id', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, id: 'CSharpRecord' });
  assert.match(errs.join('\n'), /id must be kebab-case/);
});

test('candidate: rejects unknown status', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, status: 'pending' });
  assert.match(errs.join('\n'), /status must be one of/);
});

test('candidate: rejects bad date format', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, created: '2026/04/28' });
  assert.match(errs.join('\n'), /created must be YYYY-MM-DD/);
});

test('candidate: rejects negative occurrences', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, occurrences: -1 });
  assert.match(errs.join('\n'), /occurrences/);
});

test('candidate: rejects empty features when occurrences > 0', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, features: [] });
  assert.match(errs.join('\n'), /features cannot be empty/);
});

test('candidate: accepts UNTESTED replay state', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, held_out_replay: 'UNTESTED' });
  assert.deepEqual(errs, []);
});

test('candidate: rejects unknown destination', () => {
  const errs = validateCandidateFrontmatter({ ...validCandidate, destination: 'global' });
  assert.match(errs.join('\n'), /destination must be one of/);
});

test('graveyard: example validates', () => {
  assert.deepEqual(validateGraveyardFrontmatter(validGraveyard), []);
});

test('graveyard: rejects unknown reason', () => {
  const errs = validateGraveyardFrontmatter({ ...validGraveyard, reason: 'just-because' });
  assert.match(errs.join('\n'), /reason must be one of/);
});

test('graveyard: accepts demoted-from-promoted', () => {
  const errs = validateGraveyardFrontmatter({ ...validGraveyard, last_status_before: 'promoted' });
  assert.deepEqual(errs, []);
});

test('usage: example validates', () => {
  assert.deepEqual(validateUsageRecord(validUsage), []);
});

test('usage: accepts numeric edit_distance', () => {
  const errs = validateUsageRecord({ ...validUsage, edit_distance: 0.42 });
  assert.deepEqual(errs, []);
});

test('usage: rejects negative edit_distance', () => {
  const errs = validateUsageRecord({ ...validUsage, edit_distance: -1 });
  assert.match(errs.join('\n'), /edit_distance/);
});

test('usage: rejects non-ISO ts', () => {
  const errs = validateUsageRecord({ ...validUsage, ts: '2026-05-01 10:14:22' });
  assert.match(errs.join('\n'), /ts must be ISO-8601/);
});

test('usage: rejects empty session_id', () => {
  const errs = validateUsageRecord({ ...validUsage, session_id: '' });
  assert.match(errs.join('\n'), /session_id must be non-empty/);
});
