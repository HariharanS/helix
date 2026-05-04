// Asserts that hc-setup.agent.md owns the role/gates/handoff and links to
// hc-workspace-sync rather than duplicating its procedural step list.
//
// Step 5 of helix/docs/skill-projection-and-simplification-plan.md.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const HELIX_ROOT = path.resolve(__dirname, '..', '..');
const AGENT_PATH = path.join(HELIX_ROOT, '.github', 'agents', 'hc-setup.agent.md');
const SKILL_PATH = path.join(HELIX_ROOT, '.github', 'skills', 'hc-workspace-sync', 'SKILL.md');

// Stable marker token placed in hc-workspace-sync/SKILL.md just above the
// "## Workflow" heading. The skill is the canonical procedural surface.
// If someone copies the procedure into the agent file they will most likely
// also copy this marker — that's the duplication signal we lock down.
const CANONICAL_PROCEDURE_MARKER =
  'canonical-procedure-marker: this skill owns the workspace setup procedure';

// Section headings that name canonical procedural steps. They live in the
// skill; the agent must link instead of restating them.
const PROCEDURAL_HEADINGS = [
  '### 1. Confirm Helix Is Installed',
  '### 2. Validate The Registry And Workspace Inputs',
  '### 3. Run The Authoritative Setup Script',
  '### 4. Verify Definitive Outcomes',
  '#### 5a. Onboard Repos',
  '#### 5b. Refresh Repo-State',
  '#### 5c. Review Reusable Pattern Candidates',
  '#### 5d. Create Workspace Platform AGENTS.md',
  '#### 5e. Repair Code-Review-Graph',
];

test('canonical-procedure marker is present in hc-workspace-sync/SKILL.md', () => {
  const skill = fs.readFileSync(SKILL_PATH, 'utf8');
  assert.ok(
    skill.includes(CANONICAL_PROCEDURE_MARKER),
    `marker missing from ${SKILL_PATH}; place a stable HTML comment above the Workflow section so duplication can be detected`
  );
});

test('canonical-procedure marker is not duplicated into hc-setup.agent.md', () => {
  const agent = fs.readFileSync(AGENT_PATH, 'utf8');
  assert.equal(
    agent.includes(CANONICAL_PROCEDURE_MARKER),
    false,
    'hc-setup.agent.md must not duplicate the canonical-procedure marker; link to hc-workspace-sync instead'
  );
});

test('hc-setup.agent.md does not contain the canonical procedural step headings', () => {
  const agent = fs.readFileSync(AGENT_PATH, 'utf8');
  const offenders = PROCEDURAL_HEADINGS.filter((h) => agent.includes(h));
  assert.deepEqual(
    offenders,
    [],
    `hc-setup.agent.md should link to hc-workspace-sync, not duplicate procedural headings; found:\n${offenders.join('\n')}`
  );
});

test('hc-setup.agent.md links to the hc-workspace-sync skill', () => {
  const agent = fs.readFileSync(AGENT_PATH, 'utf8');
  assert.match(
    agent,
    /hc-workspace-sync/,
    'hc-setup.agent.md must reference the hc-workspace-sync skill as the canonical procedural surface'
  );
});

test('hc-setup.agent.md retains the hard rules required by Step 5', () => {
  const agent = fs.readFileSync(AGENT_PATH, 'utf8');
  const requiredRulePatterns = [
    /Do not modify product code/i,
    /Do not rewrite `helix-repos\.yml`.*`workspace\.yml`/i,
    /Do not bypass `helix\/scripts\/workspace-setup\.ps1`/i,
    /Do not continue to onboarding.*baseline.*failed/i,
    /Do not silently fall back.*CRG `mcp`/i,
  ];
  for (const pattern of requiredRulePatterns) {
    assert.match(agent, pattern, `hc-setup.agent.md is missing required hard rule matching ${pattern}`);
  }
});
