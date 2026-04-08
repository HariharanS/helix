#!/usr/bin/env node
/**
 * Helix SubagentStop Hook
 *
 * Fires when a subagent completes.
 * Logs completion for progress tracking.
 */

const fs = require('fs');

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
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
