const fs = require('fs');
const path = require('path');

function readHookInput() {
  const raw = fs.readFileSync(0, 'utf8');
  if (!raw.trim()) {
    return {};
  }

  return JSON.parse(raw);
}

function parseYamlScalar(text) {
  const value = text.trim();

  if (value === '' || value === 'null' || value === '~') {
    return null;
  }
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  if (/^-?\d+$/.test(value)) {
    return Number.parseInt(value, 10);
  }
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }

  return value;
}

function parseSimpleYaml(content) {
  const root = {};
  const stack = [{ indent: -1, value: root }];

  for (const rawLine of content.split(/\r?\n/)) {
    if (!rawLine.trim() || rawLine.trim().startsWith('#')) {
      continue;
    }

    const indent = rawLine.match(/^ */)[0].length;
    const trimmed = rawLine.trim();
    if (trimmed.startsWith('- ')) {
      continue;
    }

    const match = trimmed.match(/^([^:]+):(?:\s*(.*))?$/);
    if (!match) {
      continue;
    }

    const key = match[1].trim();
    const valueText = match[2] ?? '';

    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const parent = stack[stack.length - 1].value;
    if (valueText === '') {
      parent[key] = {};
      stack.push({ indent, value: parent[key] });
      continue;
    }

    parent[key] = parseYamlScalar(valueText);
  }

  return root;
}

function readYamlFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  return parseSimpleYaml(fs.readFileSync(filePath, 'utf8'));
}

function getActiveWorkspace(cwd) {
  const ymlPath = path.join(cwd, '.helix', 'active-workspace.yml');
  const yamlPath = path.join(cwd, '.helix', 'active-workspace.yaml');
  const parsed = readYamlFile(fs.existsSync(ymlPath) ? ymlPath : yamlPath);
  if (!parsed || !parsed.active || parsed.active === 'null') {
    return null;
  }

  return parsed.active;
}

function getCodeReviewGraphPolicy(cwd) {
  const defaults = {
    mode: 'off',
    detailLevel: 'minimal',
    maxToolCallsPerTask: 5,
    maxContextTokensPerTask: 800,
  };

  const configPath = path.join(cwd, '.helix', 'context-providers.yml');
  const parsed = readYamlFile(configPath);
  if (!parsed || !parsed.providers || !parsed.providers.code_review_graph) {
    return defaults;
  }

  const provider = parsed.providers.code_review_graph;
  return {
    mode: provider.mode || defaults.mode,
    detailLevel: provider.detail_level || defaults.detailLevel,
    maxToolCallsPerTask:
      provider.max_tool_calls_per_task || defaults.maxToolCallsPerTask,
    maxContextTokensPerTask:
      provider.max_context_tokens_per_task || defaults.maxContextTokensPerTask,
  };
}

function getCodeReviewGraphServer(cwd) {
  const mcpPath = path.join(cwd, '.mcp.json');
  if (!fs.existsSync(mcpPath)) {
    return null;
  }

  try {
    const parsed = JSON.parse(fs.readFileSync(mcpPath, 'utf8'));
    if (parsed && parsed.mcpServers && parsed.mcpServers['code-review-graph']) {
      return parsed.mcpServers['code-review-graph'];
    }
  } catch (_) {
    return null;
  }

  return null;
}

module.exports = {
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getCodeReviewGraphServer,
  readHookInput,
};
