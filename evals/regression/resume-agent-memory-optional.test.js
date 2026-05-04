// Source-level check: hc-resume.agent.md must contain the word "optional"
// near every reference to memory (.helix/memory, episodes, learnings).

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const RESUME_AGENT = path.resolve(
  __dirname, '..', '..', '.github', 'agents', 'hc-resume.agent.md'
);

test('resume-agent-memory-optional: agent file contains "optional" near memory references', () => {
  assert.ok(fs.existsSync(RESUME_AGENT), 'hc-resume.agent.md not found');
  const text = fs.readFileSync(RESUME_AGENT, 'utf8');
  const lines = text.split(/\r?\n/);

  const memoryPattern = /(\.helix\/memory|episodes|learnings|distilled memory)/i;
  const matchedLines = [];
  for (let i = 0; i < lines.length; i++) {
    if (memoryPattern.test(lines[i])) {
      matchedLines.push(i);
    }
  }

  assert.ok(matchedLines.length > 0, 'agent file should reference memory at least once');

  // The plan requires the literal word "optional" near the memory references.
  // We define "near" as the same line or within ±3 lines.
  for (const i of matchedLines) {
    const start = Math.max(0, i - 3);
    const end = Math.min(lines.length, i + 4);
    const window = lines.slice(start, end).join('\n');
    assert.match(
      window,
      /optional/i,
      `memory reference on line ${i + 1} (${lines[i].trim()}) is not marked optional within ±3 lines`
    );
  }

  // Also enforce the exact word "optional" appears at least once in the file.
  assert.match(text, /\boptional\b/i, '"optional" must appear in hc-resume.agent.md');
});
