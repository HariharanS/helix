#!/usr/bin/env node
/**
 * Helix PostToolUse Hook
 *
 * After tool execution:
 * - After git commit → suggest updating task board
 */

const { readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};
  const toolResponse = input.tool_response || '';

  const output = {
    continue: true,
  };

  // After successful git commit — remind to update task board
  if (toolName === 'execute' || toolName === 'bash') {
    const command = toolInput.command || toolInput.input || '';

    if (command.includes('git commit') && !toolResponse.includes('error') && !toolResponse.includes('failed')) {
      output.hookSpecificOutput = {
        hookEventName: 'PostToolUse',
        additionalContext:
          '[Helix] Commit created. Remember to update the task board if this completes a task.',
      };
    }
  }

  console.log(JSON.stringify(output));
}

main();
