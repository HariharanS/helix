#!/usr/bin/env node

const { logEvent, readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();

  logEvent('sessionEnd', input, {
    reason: input.reason || null,
  });
}

main();