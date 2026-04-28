#!/usr/bin/env node

const {
  appendStateDelta,
  getCodeReviewGraphPolicy,
  getRepoRoot,
  getWorkspaceState,
  isoTimestamp,
  readHookInput,
} = require('./helix-runtime');

// Emits one `session_baseline` delta capturing Helix-side state at session
// entry: workspace, workflow, phase, CRG mode. Copilot CLI itself records
// session.start (cwd, branch, copilotVersion) — we don't duplicate that.
function main() {
  const input = readHookInput();
  const repoRoot = getRepoRoot();
  const workspace = getWorkspaceState(repoRoot);
  const crg = getCodeReviewGraphPolicy(repoRoot);

  appendStateDelta(repoRoot, 'session_baseline', isoTimestamp(input), {
    source: input.source || null,
    workspace: workspace.workspaceId,
    workflow: workspace.workflow,
    phase: workspace.phase,
    last_completed_phase: workspace.lastCompletedPhase,
    crg_mode: crg.mode,
    crg_detail: crg.detailLevel,
  });
}

main();
