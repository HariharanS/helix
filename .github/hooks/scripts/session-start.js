#!/usr/bin/env node

const {
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getRepoRoot,
  logEvent,
  readHookInput,
} = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const repoRoot = getRepoRoot();
  const graphPolicy = getCodeReviewGraphPolicy(repoRoot);

  logEvent('sessionStart', input, {
    source: input.source || null,
    initialPrompt: input.initialPrompt || null,
    activeWorkspace: getActiveWorkspace(repoRoot),
    codeReviewGraphMode: graphPolicy.mode,
    codeReviewGraphDetail: graphPolicy.detailLevel,
  });
}

main();