const fs = require('fs');
const path = require('path');

function readHookInput() {
  const raw = fs.readFileSync(0, 'utf8');
  if (!raw.trim()) {
    return {};
  }
  return JSON.parse(raw);
}

function ensureDirectory(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function getHooksRoot() {
  return process.cwd();
}

function getRepoRoot() {
  return path.resolve(getHooksRoot(), '..', '..');
}

function getStateDeltaPath(repoRoot = getRepoRoot()) {
  return path.join(repoRoot, '.helix', 'state-deltas.jsonl');
}

function getHookEventPath(repoRoot = getRepoRoot()) {
  return path.join(repoRoot, '.helix', 'hook-events.jsonl');
}

function appendJsonl(filePath, record) {
  ensureDirectory(path.dirname(filePath));
  fs.appendFileSync(filePath, `${JSON.stringify(record)}\n`, 'utf8');
}

function redactText(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return value;
  }
  let redacted = value;
  const replacements = [
    [/\bgh[pousr]_[A-Za-z0-9]{20,}\b/g, '[REDACTED_TOKEN]'],
    [/\bgithub_pat_[A-Za-z0-9_]{20,}\b/g, '[REDACTED_TOKEN]'],
    [/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer [REDACTED]'],
    [/--password(?:=|\s+)\S+/gi, '--password=[REDACTED]'],
    [/--token(?:=|\s+)\S+/gi, '--token=[REDACTED]'],
  ];
  for (const [pattern, replacement] of replacements) {
    redacted = redacted.replace(pattern, replacement);
  }
  return redacted;
}

function truncateText(value, maxLength = 400) {
  if (typeof value !== 'string' || value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, maxLength)}...<truncated>`;
}

function sanitizeForLog(value) {
  if (typeof value === 'string') {
    return truncateText(redactText(value));
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeForLog);
  }
  if (value && typeof value === 'object') {
    const sanitized = {};
    for (const [key, entry] of Object.entries(value)) {
      sanitized[key] = sanitizeForLog(entry);
    }
    return sanitized;
  }
  return value ?? null;
}

function safeParseJson(raw) {
  if (typeof raw !== 'string' || raw.trim().length === 0) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function parseToolArgs(raw) {
  if (raw && typeof raw === 'object') {
    return raw;
  }
  return safeParseJson(raw);
}

function parseYamlScalar(text) {
  const value = text.trim();
  if (value === '' || value === 'null' || value === '~') return null;
  if (value === 'true') return true;
  if (value === 'false') return false;
  if (/^-?\d+$/.test(value)) return Number.parseInt(value, 10);
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  return value;
}

function parseSimpleYaml(content) {
  const root = {};
  const stack = [{ indent: -1, value: root }];
  for (const rawLine of content.split(/\r?\n/)) {
    if (!rawLine.trim() || rawLine.trim().startsWith('#')) continue;
    const indent = rawLine.match(/^ */)[0].length;
    const trimmed = rawLine.trim();
    if (trimmed.startsWith('- ')) continue;
    const match = trimmed.match(/^([^:]+):(?:\s*(.*))?$/);
    if (!match) continue;
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
  if (!fs.existsSync(filePath)) return null;
  return parseSimpleYaml(fs.readFileSync(filePath, 'utf8'));
}

function getActiveWorkspace(repoRoot = getRepoRoot()) {
  const ymlPath = path.join(repoRoot, '.helix', 'active-workspace.yml');
  const yamlPath = path.join(repoRoot, '.helix', 'active-workspace.yaml');
  const parsed = readYamlFile(fs.existsSync(ymlPath) ? ymlPath : yamlPath);
  if (!parsed || !parsed.active || parsed.active === 'null') return null;
  return parsed.active;
}

function getCodeReviewGraphPolicy(repoRoot = getRepoRoot()) {
  const defaults = { mode: 'off', detailLevel: 'minimal' };
  const configPath = path.join(repoRoot, '.helix', 'context-providers.yml');
  const parsed = readYamlFile(configPath);
  if (!parsed || !parsed.providers || !parsed.providers.code_review_graph) return defaults;
  const provider = parsed.providers.code_review_graph;
  return {
    mode: provider.mode || defaults.mode,
    detailLevel: provider.detail_level || defaults.detailLevel,
  };
}

// Reads the active workspace's workflow + phase. Returns nulls when no
// workspace is active or its manifest is unreadable. `workflow` defaults to
// 'full-rpi' (the only workflow today); leave as opaque string so future
// workflow types do not require a schema migration.
function getWorkspaceState(repoRoot = getRepoRoot()) {
  const workspaceId = getActiveWorkspace(repoRoot);
  if (!workspaceId) {
    return { workspaceId: null, workflow: null, phase: null, lastCompletedPhase: null };
  }
  const wsYml = path.join(repoRoot, 'workspaces', workspaceId, 'workspace.yml');
  const wsYaml = path.join(repoRoot, 'workspaces', workspaceId, 'workspace.yaml');
  const parsed = readYamlFile(fs.existsSync(wsYml) ? wsYml : wsYaml);
  if (!parsed) {
    return { workspaceId, workflow: 'full-rpi', phase: null, lastCompletedPhase: null };
  }
  return {
    workspaceId,
    workflow: parsed.workflow || 'full-rpi',
    phase: parsed.phase?.current || null,
    lastCompletedPhase: parsed.phase?.last_completed || null,
  };
}

function isoTimestamp(input) {
  const ms = typeof input?.timestamp === 'number' ? input.timestamp : Date.now();
  return new Date(ms).toISOString();
}

function hookInputField(input, ...keys) {
  if (!input || typeof input !== 'object') {
    return null;
  }
  for (const key of keys) {
    if (input[key] !== undefined && input[key] !== null) {
      return input[key];
    }
  }
  return null;
}

function appendHookEvent(repoRoot, eventType, input = {}, fields = {}) {
  const record = {
    ...sanitizeForLog(fields),
    schema_version: 1,
    ts: isoTimestamp(input),
    event_type: eventType,
    hook_name: hookInputField(input, 'hook', 'hookName', 'hook_event_name'),
    source: hookInputField(input, 'source'),
    copilot_session_id: hookInputField(input, 'session_id', 'sessionId'),
    tool_call_id: hookInputField(input, 'tool_call_id', 'toolCallId'),
  };
  appendJsonl(getHookEventPath(repoRoot), record);
}

function logEvent(eventType, input = {}, fields = {}) {
  appendHookEvent(getRepoRoot(), eventType, input, fields);
}

// Append one Helix state-delta record. Schema (all opaque strings, schema-ready
// for future workflows):
//   { ts, delta_type, workspace, workflow, phase, ...extras }
// `delta_type`: 'session_baseline' | 'workspace_change' | 'phase_change' |
//   'workflow_change' | 'crg_change' | 'slice_gate' | <future>.
function appendStateDelta(repoRoot, deltaType, ts, fields = {}) {
  const record = { ts, delta_type: deltaType, ...fields };
  appendJsonl(getStateDeltaPath(repoRoot), record);
}

module.exports = {
  appendHookEvent,
  appendStateDelta,
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getHookEventPath,
  getRepoRoot,
  getStateDeltaPath,
  getWorkspaceState,
  isoTimestamp,
  logEvent,
  parseSimpleYaml,
  parseToolArgs,
  readHookInput,
  readYamlFile,
  redactText,
  sanitizeForLog,
  truncateText,
};
