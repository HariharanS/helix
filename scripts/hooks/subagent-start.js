#!/usr/bin/env node
/**
 * Helix SubagentStart Hook
 *
 * Fires when a subagent is spawned.
 * Injects relevant context: active workspace info, repo AGENTS.md summary.
 */

const fs = require('fs');
const path = require('path');

function parseYamlValue(content, key) {
  const match = content.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  return match ? match[1].trim() : null;
}

function main() {
  const input = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'));
  const cwd = input.cwd || process.cwd();
  const agentType = input.agent_type || 'unknown';

  const contextParts = [];

  // 1. Inject active workspace context
  const activeWsPath = path.join(cwd, '.helix', 'active-workspace.yaml');
  if (fs.existsSync(activeWsPath)) {
    const content = fs.readFileSync(activeWsPath, 'utf8');
    const active = parseYamlValue(content, 'active');
    if (active && active !== 'null') {
      contextParts.push(`[Helix] Active workspace: ${active}`);

      // Inject workspace.yaml summary if it exists
      const wsYamlPath = path.join(cwd, 'workspaces', active, 'workspace.yaml');
      if (fs.existsSync(wsYamlPath)) {
        const wsContent = fs.readFileSync(wsYamlPath, 'utf8');
        contextParts.push(`[Helix] Workspace config:\n${wsContent}`);
      }
    }
  }

  // 2. Inject repo AGENTS.md if working in a service repo
  const agentsMdPath = path.join(cwd, 'AGENTS.md');
  if (fs.existsSync(agentsMdPath)) {
    const content = fs.readFileSync(agentsMdPath, 'utf8');
    // Inject just the first 100 lines (summary) to avoid context bloat
    const summary = content.split('\n').slice(0, 100).join('\n');
    contextParts.push(`[Helix] Repo context from AGENTS.md:\n${summary}`);
  }

  const output = {
    continue: true,
  };

  if (contextParts.length > 0) {
    output.hookSpecificOutput = {
      hookEventName: 'SubagentStart',
      additionalContext: contextParts.join('\n\n'),
    };
  }

  console.log(JSON.stringify(output));
}

main();
