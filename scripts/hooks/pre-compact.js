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

  // Save compaction marker to episodic memory
  const episodesDir = path.join(cwd, '.helix', 'memory', 'episodes');

  if (fs.existsSync(episodesDir)) {
    const markerPath = path.join(episodesDir, `.compaction-${sessionId}.tmp`);
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
