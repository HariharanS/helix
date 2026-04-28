#!/usr/bin/env node
// Helix CRG sweep — multi-repo aware incremental graph update.
// Wired into Copilot CLI subagentStop (per work-unit trigger) and sessionEnd (final backstop).
// For each repo under workspaces/{active}/repos/*, compares git HEAD against last-seen
// state and fires a detached `code_review_graph update` only for repos whose HEAD moved.

const fs = require('fs');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const {
  getActiveWorkspace,
  getCodeReviewGraphPolicy,
  getRepoRoot,
  logEvent,
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

function main() {
  // Drain stdin even when payload is unused; some hook hosts block on EOF.
  let input = {};
  try {
    input = readHookInput();
  } catch {
    // Ignore — hook input is optional for this sweep.
  }

  const repoRoot = getRepoRoot();
  const policy = getCodeReviewGraphPolicy(repoRoot);

  if (policy.mode !== 'mcp') {
    logEvent('crgSweep', input, { skipped: true, reason: `mode=${policy.mode}` });
    return;
  }

  const workspace = getActiveWorkspace(repoRoot);
  if (!workspace) {
    logEvent('crgSweep', input, { skipped: true, reason: 'no-active-workspace' });
    return;
  }

  const repos = listWorkspaceRepos(repoRoot, workspace);
  if (repos.length === 0) {
    logEvent('crgSweep', input, { skipped: true, reason: 'no-repos', workspace });
    return;
  }

  const runner = findPythonRunner();
  if (!runner) {
    logEvent('crgSweep', input, { skipped: true, reason: 'no-python-runner', workspace });
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
      pid = spawnDetachedUpdate(runner, repo.path, logFile);
    } catch (error) {
      logEvent('crgSweepRepoError', input, {
        workspace,
        repo: repo.id,
        error: error && error.message ? error.message : String(error),
      });
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

  logEvent('crgSweep', input, {
    workspace,
    runner: runner.command,
    triggered,
    unchanged,
  });
}

main();
