#!/usr/bin/env node

const { logEvent, parseToolArgs, readHookInput } = require('./helix-runtime');

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

  logEvent('postToolUse', input, {
    toolName: input.toolName || null,
    toolArgs: input.toolArgs || null,
    command: extractCommand(toolArgs),
    toolResult: input.toolResult || null,
  });
}

main();