#!/usr/bin/env node

// Detects when distillation is due based on active-workspace phase state and
// emits a `distill_trigger` state-delta + a stderr reminder. Does NOT invoke
// the distiller agent — distillation requires LLM reasoning and is too
// expensive for a sessionEnd hook. Operator runs `/distill` in the next
// interactive session when prompted (or when they want to anyway).
//
// See helix/docs/distillation-architecture.md for the trigger heuristic and
// rationale.

const {
  appendStateDelta,
  getRepoRoot,
  getWorkspaceState,
  isoTimestamp,
  readHookInput,
} = require('./helix-runtime');

// Heuristic: distillation is due when the workspace is actively in the distill
// phase, or has just completed review (distill is next).
function isDistillationDue(workspace) {
  if (!workspace.workspaceId) return false;
  if (workspace.phase === 'distill') return true;
  if (workspace.lastCompletedPhase === 'review') return true;
  return false;
}

function main() {
  try {
    const input = readHookInput();
    const repoRoot = getRepoRoot();
    const ws = getWorkspaceState(repoRoot);
    if (!isDistillationDue(ws)) return;

    const ts = isoTimestamp(input);
    appendStateDelta(repoRoot, 'distill_trigger', ts, {
      workspace: ws.workspaceId,
      workflow: ws.workflow,
      phase: ws.phase,
      last_completed_phase: ws.lastCompletedPhase,
      reason: ws.phase === 'distill' ? 'phase_active' : 'review_completed',
    });
    process.stderr.write(
      `[distill-trigger] workspace=${ws.workspaceId} phase=${ws.phase || '-'} ` +
      `last_completed=${ws.lastCompletedPhase || '-'} -> distillation due. ` +
      `Run /distill in the next session.\n`
    );
  } catch (err) {
    // Hooks must never abort the host. Surface and exit 0.
    process.stderr.write(`[distill-trigger] ${err.stack || err.message}\n`);
  }
}

if (require.main === module) main();

module.exports = { isDistillationDue };
