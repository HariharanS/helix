#!/usr/bin/env node
/**
 * Helix SubagentStart Hook
 *
 * Fires when a subagent is spawned.
 * Injects relevant context: AGENTS.md summary, active task info.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
  const cwd = input.cwd || process.cwd();
  const agentType = input.agent_type || 'unknown';

  const contextParts = [];

  // Inject repo AGENTS.md if working in a service repo
  const agentsMdPath = path.join(cwd, 'AGENTS.md');
  if (fs.existsSync(agentsMdPath)) {
    const content = fs.readFileSync(agentsMdPath, 'utf8');
    // Inject just the first 100 lines (summary) to avoid context bloat
    const summary = content.split('\n').slice(0, 100).join('\n');
    contextParts.push(`[Helix] Repo context from AGENTS.md:\n${summary}`);
  }

  const output = {
    continue: true,
  };

  if (contextParts.length > 0) {
    output.hookSpecificOutput = {
      hookEventName: 'SubagentStart',
      additionalContext: contextParts.join('\n\n'),
    };
  }

  console.log(JSON.stringify(output));
}

main();
