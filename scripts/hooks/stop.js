#!/usr/bin/env node
/**
 * Helix Stop Hook
 *
 * Fires when the agent session ends.
 * Reminds to run distill if significant work was done.
 */

const { readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();

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
