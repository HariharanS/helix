#!/usr/bin/env node
/**
 * Helix SessionStart Hook
 *
 * Fires when a new session begins or resumes.
 * Loads active workspace context, memory index, and task boards.
 */

const fs = require('fs');
const path = require('path');
const {
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getCodeReviewGraphServer,
  readHookInput,
} = require('./helix-runtime');

function main() {
  const input = readHookInput();
  const cwd = input.cwd || process.cwd();

  const messages = [];

  // 1. Check active workspace
  const activeWorkspace = getActiveWorkspace(cwd);
  if (activeWorkspace) {
    messages.push(`[Helix] Active workspace: ${activeWorkspace}`);
  } else {
    messages.push('[Helix] No active workspace. Use workspace-sync to set one up.');
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

  // 5. Check optional context provider state
  const graphPolicy = getCodeReviewGraphPolicy(cwd);
  if (graphPolicy.mode === 'off') {
    messages.push('[Helix Context] code-review-graph: off.');
  } else {
    const server = getCodeReviewGraphServer(cwd);
    const command =
      server && server.command
        ? ` via ${server.command}${Array.isArray(server.args) && server.args.length ? ` ${server.args.join(' ')}` : ''}`
        : ' (MCP server missing from .mcp.json)';
    messages.push(
      `[Helix Context] code-review-graph: ${graphPolicy.mode}, detail=${graphPolicy.detailLevel}, budget=${graphPolicy.maxToolCallsPerTask} calls/${graphPolicy.maxContextTokensPerTask} tokens${command}.`
    );
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
