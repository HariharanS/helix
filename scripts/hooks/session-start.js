#!/usr/bin/env node
/**
 * Helix SessionStart Hook
 *
 * Fires when a new session begins or resumes.
 * Loads memory index and active task board into context.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
  const cwd = input.cwd || process.cwd();

  const messages = [];

  // Check for memory index
  const memoryPaths = [
    path.join(cwd, 'memory', 'index.md'),
    path.join(cwd, '..', 'helix', 'memory', 'index.md'),
  ];

  for (const memPath of memoryPaths) {
    if (fs.existsSync(memPath)) {
      const content = fs.readFileSync(memPath, 'utf8');
      if (content.trim() && !content.includes('No episodes recorded')) {
        messages.push(`[Helix Memory] Loaded memory index from ${memPath}`);
      }
      break;
    }
  }

  // Check for active task boards
  const taskBoardPaths = [
    path.join(cwd, 'task-boards'),
    path.join(cwd, '..', 'helix', 'task-boards'),
  ];

  for (const tbPath of taskBoardPaths) {
    if (fs.existsSync(tbPath)) {
      const files = fs.readdirSync(tbPath).filter(f => f.endsWith('.md'));
      if (files.length > 0) {
        messages.push(`[Helix] Active task boards: ${files.join(', ')}`);
      }
      break;
    }
  }

  // Output
  const output = {
    continue: true,
  };

  if (messages.length > 0) {
    output.hookSpecificOutput = {
      hookEventName: 'SessionStart',
      additionalContext: messages.join('\n'),
    };
  }

  console.log(JSON.stringify(output));
}

main();
