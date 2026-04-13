#!/usr/bin/env node

const { logEvent, parseToolArgs, readHookInput } = require('./helix-runtime');

const DANGEROUS_COMMANDS = [
  {
    pattern: /\b(sudo|su|runas)\b/i,
    reason: 'Privilege escalation requires manual approval.',
  },
  {
    pattern: /rm\s+-rf\s*\/(\s|$)|rm\s+.*-rf\s*\/(\s|$)/i,
    reason: 'Destructive operations targeting the filesystem root require manual approval.',
  },
  {
    pattern: /\b(mkfs|dd|format)\b/i,
    reason: 'System-level destructive operations are not allowed via automated execution.',
  },
  {
    pattern: /curl.*\|\s*(bash|sh)|wget.*\|\s*(bash|sh)|iex\s*\(\s*irm/i,
    reason: 'Download-and-execute patterns require manual approval.',
  },
  {
    pattern: /git\s+push\s+--force(\s+origin)?\s+(main|master)\b/i,
    reason: 'Force-pushing the default branch requires manual approval.',
  },
  {
    pattern: /git\s+reset\s+--hard\b/i,
    reason: 'git reset --hard requires manual approval.',
  },
  {
    pattern: /\bdrop\s+table\b/i,
    reason: 'DROP TABLE statements require manual approval.',
  },
];

function extractCommand(toolArgs) {
  if (!toolArgs || typeof toolArgs !== 'object') {
    return '';
  }

  if (typeof toolArgs.command === 'string') {
    return toolArgs.command;
  }

  if (typeof toolArgs.input === 'string') {
    return toolArgs.input;
  }

  return '';
}

function main() {
  const input = readHookInput();
  const toolArgs = parseToolArgs(input.toolArgs);
  const command = extractCommand(toolArgs);

  logEvent('preToolUse', input, {
    toolName: input.toolName || null,
    toolArgs: input.toolArgs || null,
    command,
  });

  if (!command) {
    return;
  }

  for (const rule of DANGEROUS_COMMANDS) {
    if (rule.pattern.test(command)) {
      process.stdout.write(
        JSON.stringify({
          permissionDecision: 'deny',
          permissionDecisionReason: rule.reason,
        })
      );
      return;
    }
  }
}

main();