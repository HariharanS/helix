#!/usr/bin/env node

const { logEvent, readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();

  logEvent('errorOccurred', input, {
    error: input.error || null,
  });
}

main();