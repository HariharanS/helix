#!/usr/bin/env node

const { logEvent, readHookInput, sanitizeForLog } = require('./helix-runtime');

function main() {
  const input = readHookInput();

  logEvent('subagentStop', input, {
    payload: sanitizeForLog(input),
  });
}

main();