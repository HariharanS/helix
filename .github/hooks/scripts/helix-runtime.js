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

function getAuditLogPath() {
  return path.join(getHooksRoot(), 'logs', 'audit.jsonl');
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

function getActiveWorkspace(repoRoot = getRepoRoot()) {
  const ymlPath = path.join(repoRoot, '.helix', 'active-workspace.yml');
  const yamlPath = path.join(repoRoot, '.helix', 'active-workspace.yaml');
  const parsed = readYamlFile(fs.existsSync(ymlPath) ? ymlPath : yamlPath);
  if (!parsed || !parsed.active || parsed.active === 'null') {
    return null;
  }

  return parsed.active;
}

function getCodeReviewGraphPolicy(repoRoot = getRepoRoot()) {
  const defaults = {
    mode: 'off',
    detailLevel: 'minimal',
  };

  const configPath = path.join(repoRoot, '.helix', 'context-providers.yml');
  const parsed = readYamlFile(configPath);
  if (!parsed || !parsed.providers || !parsed.providers.code_review_graph) {
    return defaults;
  }

  const provider = parsed.providers.code_review_graph;
  return {
    mode: provider.mode || defaults.mode,
    detailLevel: provider.detail_level || defaults.detailLevel,
  };
}

function logEvent(event, input, details = {}) {
  const record = sanitizeForLog({
    event,
    timestamp: typeof input.timestamp === 'number' ? input.timestamp : Date.now(),
    cwd: input.cwd || getRepoRoot(),
    ...details,
  });

  appendJsonl(getAuditLogPath(), record);
}

module.exports = {
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getRepoRoot,
  logEvent,
  parseToolArgs,
  readHookInput,
  sanitizeForLog,
};