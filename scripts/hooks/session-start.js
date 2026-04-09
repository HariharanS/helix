#!/usr/bin/env node
/**
 * Helix SessionStart Hook
 *
 * Fires when a new session begins or resumes.
 * Loads active workspace context, memory index, and task boards.
 */

const fs = require('fs');
const path = require('path');
const yaml = require === undefined ? null : null; // yaml parsing done manually below

function parseYaml(content) {
  // Simple YAML value parser for key: value pairs
  const result = {};
  for (const line of content.split('\n')) {
    const match = line.match(/^(\w+):\s*(.+)$/);
    if (match) {
      result[match[1]] = match[2].trim();
    }
  }
  return result;
}

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
  const cwd = input.cwd || process.cwd();

  const messages = [];

  // 1. Check active workspace
  const activeWsPath = path.join(cwd, '.helix', 'active-workspace.yaml');
  let activeWorkspace = null;

  if (fs.existsSync(activeWsPath)) {
    const content = fs.readFileSync(activeWsPath, 'utf8');
    const parsed = parseYaml(content);
    if (parsed.active && parsed.active !== 'null') {
      activeWorkspace = parsed.active;
      messages.push(`[Helix] Active workspace: ${activeWorkspace}`);
    } else {
      messages.push('[Helix] No active workspace. Use workspace-sync to set one up.');
    }
  }

  // 2. Check memory index
  const memoryIndexPath = path.join(cwd, '.helix', 'memory', 'index.md');
  if (fs.existsSync(memoryIndexPath)) {
    const content = fs.readFileSync(memoryIndexPath, 'utf8');
    if (content.trim() && !content.includes('No episodes recorded')) {
      messages.push(`[Helix Memory] Loaded memory index.`);
    }
  }

  // 3. Check workspace task boards
  if (activeWorkspace) {
    const tbPath = path.join(cwd, 'workspaces', activeWorkspace, 'task-boards');
    if (fs.existsSync(tbPath)) {
      const files = fs.readdirSync(tbPath).filter(f => f.endsWith('.md'));
      if (files.length > 0) {
        messages.push(`[Helix] Task boards: ${files.join(', ')}`);
      }
    }

    // 4. Check workspace decisions
    const decPath = path.join(cwd, 'workspaces', activeWorkspace, 'decisions');
    if (fs.existsSync(decPath)) {
      const files = fs.readdirSync(decPath).filter(f => f.endsWith('.md'));
      if (files.length > 0) {
        messages.push(`[Helix] Decisions logs: ${files.join(', ')}`);
      }
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
