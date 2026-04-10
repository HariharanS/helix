#!/usr/bin/env node
/**
 * Helix SubagentStop Hook
 *
 * Fires when a subagent completes.
 * Logs completion for progress tracking.
 */

const { readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const agentId = input.agent_id || 'unknown';
  const agentType = input.agent_type || 'unknown';

  const output = {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'SubagentStop',
      additionalContext: `[Helix] Subagent completed: ${agentType} (${agentId})`,
    },
  };

  console.log(JSON.stringify(output));
}

main();
