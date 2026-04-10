#!/usr/bin/env node
/**
 * Helix PreToolUse Hook
 *
 * Safety gate for tool executions:
 * - Intercept git commit → remind to run tests first
 * - Block dangerous operations
 */

const { readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};

  const output = {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'allow',
    },
  };

  // Gate: git commit — remind about tests
  if (toolName === 'execute' || toolName === 'bash') {
    const command = toolInput.command || toolInput.input || '';

    // Warn on git commit without test evidence
    if (command.includes('git commit') && !command.includes('--amend')) {
      output.hookSpecificOutput.additionalContext =
        '[Helix] Committing code. Ensure tests have been run and are green before this commit.';
    }

    // Block dangerous operations
    const dangerous = [
      'rm -rf /',
      'git push --force main',
      'git push --force master',
      'git reset --hard',
      'drop table',
      'DROP TABLE',
    ];

    for (const pattern of dangerous) {
      if (command.includes(pattern)) {
        output.hookSpecificOutput.permissionDecision = 'deny';
        output.hookSpecificOutput.permissionDecisionReason =
          `[Helix] Blocked dangerous operation: "${pattern}". This requires explicit human approval.`;
        break;
      }
    }
  }

  console.log(JSON.stringify(output));
}

main();
