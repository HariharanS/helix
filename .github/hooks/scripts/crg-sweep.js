#!/usr/bin/env node
// Helix CRG sweep — multi-repo aware incremental graph update.
// Wired into Copilot CLI subagentStop (per work-unit trigger) and sessionEnd (final backstop).
// For each repo under workspaces/{active}/repos/*, compares git HEAD against last-seen
// state and fires a detached `code_review_graph update` only for repos whose HEAD moved.

const fs = require('fs');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const {
  appendHookEvent,
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getRepoRoot,
  readHookInput,
} = require('./helix-runtime');

const STATE_REL = '.helix/crg-update-state.json';

function readState(repoRoot) {
  const filePath = path.join(repoRoot, STATE_REL);
  if (!fs.existsSync(filePath)) return { repos: {} };
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : { repos: {} };
  } catch {
    return { repos: {} };
  }
}

function writeState(repoRoot, state) {
  const filePath = path.join(repoRoot, STATE_REL);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

function gitHead(repoPath) {
  try {
    return execFileSync('git', ['-C', repoPath, 'rev-parse', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 3000,
    }).trim();
  } catch {
    return null;
  }
}

function findPythonRunner() {
  const candidates = [
    { command: 'python', args: [] },
    { command: 'py', args: ['-3'] },
    { command: 'python3', args: [] },
  ];

  for (const candidate of candidates) {
    try {
      execFileSync(candidate.command, [...candidate.args, '-c', 'import code_review_graph'], {
        stdio: 'ignore',
        timeout: 3000,
      });
      return candidate;
    } catch {
      // try next
    }
  }
  return null;
}

function spawnDetachedUpdate(runner, repoPath, logFile) {
  const out = fs.openSync(logFile, 'a');
  fs.writeSync(out, `--- ${new Date().toISOString()} update --repo ${repoPath}\n`);
  const child = spawn(
    runner.command,
    [...runner.args, '-m', 'code_review_graph', 'update', '--repo', repoPath],
    { detached: true, stdio: ['ignore', out, out] }
  );
  child.unref();
  return child.pid;
}

function listWorkspaceRepos(repoRoot, workspace) {
  const reposDir = path.join(repoRoot, 'workspaces', workspace, 'repos');
  if (!fs.existsSync(reposDir)) return [];
  return fs
    .readdirSync(reposDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => ({
      id: entry.name,
      path: path.join(reposDir, entry.name),
    }))
    .filter((repo) => fs.existsSync(path.join(repo.path, '.git')));
}

function recordHookEvent(repoRoot, eventType, input, fields, appendEvent = appendHookEvent) {
  try {
    appendEvent(repoRoot, eventType, input, fields);
  } catch (error) {
    const message = error && error.message ? error.message : String(error);
    process.stderr.write(`[crg-sweep] failed to append hook event: ${message}\n`);
  }
}

function main(deps = {}) {
  const readInput = deps.readHookInput || readHookInput;
  const appendEvent = deps.appendHookEvent || appendHookEvent;
  const findRunner = deps.findPythonRunner || findPythonRunner;
  const spawnUpdate = deps.spawnDetachedUpdate || spawnDetachedUpdate;

  // Drain stdin even when payload is unused; some hook hosts block on EOF.
  let input = {};
  try {
    input = readInput();
  } catch {
    // Ignore — hook input is optional for this sweep.
  }

  const repoRoot = getRepoRoot();
  const policy = getCodeReviewGraphPolicy(repoRoot);

  if (policy.mode !== 'mcp') {
    recordHookEvent(repoRoot, 'crgSweep', input, { skipped: true, reason: `mode=${policy.mode}` }, appendEvent);
    return;
  }

  const workspace = getActiveWorkspace(repoRoot);
  if (!workspace) {
    recordHookEvent(repoRoot, 'crgSweep', input, { skipped: true, reason: 'no-active-workspace' }, appendEvent);
    return;
  }

  const repos = listWorkspaceRepos(repoRoot, workspace);
  if (repos.length === 0) {
    recordHookEvent(repoRoot, 'crgSweep', input, { skipped: true, reason: 'no-repos', workspace }, appendEvent);
    return;
  }

  const runner = findRunner();
  if (!runner) {
    recordHookEvent(repoRoot, 'crgSweep', input, { skipped: true, reason: 'no-python-runner', workspace }, appendEvent);
    return;
  }

  const state = readState(repoRoot);
  if (!state.repos || typeof state.repos !== 'object') {
    state.repos = {};
  }

  const logsDir = path.join(repoRoot, '.helix', 'logs');
  fs.mkdirSync(logsDir, { recursive: true });
  const logFile = path.join(logsDir, 'crg-update.log');

  const triggered = [];
  const unchanged = [];

  for (const repo of repos) {
    const head = gitHead(repo.path);
    if (!head) continue;

    const previous = state.repos[repo.id];
    if (previous && previous.head === head) {
      unchanged.push(repo.id);
      continue;
    }

    let pid = null;
    try {
      pid = spawnUpdate(runner, repo.path, logFile);
    } catch (error) {
      recordHookEvent(repoRoot, 'crgSweepRepoError', input, {
        workspace,
        repo: repo.id,
        error: error && error.message ? error.message : String(error),
      }, appendEvent);
      continue;
    }

    state.repos[repo.id] = {
      head,
      last_updated_at: new Date().toISOString(),
      last_pid: pid,
    };
    triggered.push({ id: repo.id, head: head.slice(0, 7), pid });
  }

  writeState(repoRoot, state);

  recordHookEvent(repoRoot, 'crgSweep', input, {
    workspace,
    runner: runner.command,
    triggered,
    unchanged,
  }, appendEvent);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`[crg-sweep] ${error.stack || error.message || String(error)}\n`);
  }
}

module.exports = {
  findPythonRunner,
  gitHead,
  listWorkspaceRepos,
  main,
  readState,
  recordHookEvent,
  writeState,
};
