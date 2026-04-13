#!/usr/bin/env node

const { logEvent, readHookInput } = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const prompt = typeof input.prompt === 'string' ? input.prompt : '';

  logEvent('userPromptSubmitted', input, {
    prompt,
    promptLength: prompt.length,
  });
}

main();