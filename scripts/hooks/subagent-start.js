#!/usr/bin/env node
/**
 * Helix SubagentStart Hook
 *
 * Fires when a subagent is spawned.
 * Injects relevant context: active workspace info, repo AGENTS.md summary.
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
  const agentType = input.agent_type || 'unknown';

  const contextParts = [];

  // 1. Inject active workspace context
  const active = getActiveWorkspace(cwd);
  if (active) {
    contextParts.push(`[Helix] Active workspace: ${active}`);

    // Inject workspace manifest summary if it exists
    const wsYamlPath = fs.existsSync(path.join(cwd, 'workspaces', active, 'workspace.yml'))
      ? path.join(cwd, 'workspaces', active, 'workspace.yml')
      : path.join(cwd, 'workspaces', active, 'workspace.yaml');
    if (fs.existsSync(wsYamlPath)) {
      const wsContent = fs.readFileSync(wsYamlPath, 'utf8');
      contextParts.push(`[Helix] Workspace config:\n${wsContent}`);
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

  // 3. Inject optional graph policy when enabled
  const graphPolicy = getCodeReviewGraphPolicy(cwd);
  if (graphPolicy.mode !== 'off') {
    const server = getCodeReviewGraphServer(cwd);
    const toolHints = [
      'Prefer `get_review_context_tool`, `get_impact_radius_tool`, `detect_changes_tool`, and targeted `query_graph_tool` calls.',
      'Keep detail level at minimal unless a narrower answer fails.',
      `Stay within ${graphPolicy.maxToolCallsPerTask} graph calls and ${graphPolicy.maxContextTokensPerTask} graph-context tokens per task.`,
    ];

    if (graphPolicy.mode === 'review-only') {
      toolHints.unshift('Use code-review-graph only for review scoping, blast radius, and changed-file context. Fall back to manual repo search for general implementation discovery.');
    } else {
      toolHints.unshift('Use code-review-graph to narrow code reads before broad workspace scans, then validate the result against repo conventions and workspace artifacts.');
    }

    if (!server) {
      toolHints.push('The provider is enabled in Helix but no `code-review-graph` MCP server is configured in `.mcp.json` yet.');
    }

    contextParts.push(
      `[Helix] Optional context provider: code-review-graph (${graphPolicy.mode}, agent=${agentType}).\n- ${toolHints.join('\n- ')}`
    );
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
