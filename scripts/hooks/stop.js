#!/usr/bin/env node
/**
 * Helix Stop Hook
 *
 * Fires when the agent session ends.
 * Reminds to run distill if significant work was done.
 */

const fs = require('fs');

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));

  const output = {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'Stop',
      additionalContext:
        '[Helix] Session ending. Consider running /distill to extract learnings from this session.',
    },
  };

  console.log(JSON.stringify(output));
}

main();
