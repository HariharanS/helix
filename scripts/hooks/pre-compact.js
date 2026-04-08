#!/usr/bin/env node
/**
 * Helix PreCompact Hook
 *
 * Fires before context compaction.
 * Saves session state snapshot to preserve critical information.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
  const cwd = input.cwd || process.cwd();
  const sessionId = input.sessionId || 'unknown';
  const timestamp = new Date().toISOString();

  // Attempt to save a compaction marker to episodic memory
  const memoryDirs = [
    path.join(cwd, '.copilot', 'memory', 'episodes'),
    path.join(cwd, 'memory', 'episodes'),
  ];

  for (const dir of memoryDirs) {
    if (fs.existsSync(dir)) {
      const markerPath = path.join(dir, `.compaction-${sessionId}.tmp`);
      try {
        fs.writeFileSync(markerPath, JSON.stringify({
          timestamp,
          sessionId,
          event: 'pre-compaction',
          note: 'Context was compacted. Check session history for full details.',
        }, null, 2));
      } catch (e) {
        // Non-critical — don't block on write failure
      }
      break;
    }
  }

  const output = {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'PreCompact',
      additionalContext:
        '[Helix] Context compaction occurring. Critical session state should be persisted to task board or decisions log before compaction.',
    },
  };

  console.log(JSON.stringify(output));
}

main();
