#!/usr/bin/env node

// Idempotent spawner for the Helix floating pet (helix/pet/pet-host.ps1).
// Invoked from the Copilot sessionStart hook. Reads helix/pet/pet-host.pid;
// if a live process already owns it, exits silently. Otherwise launches a new
// hidden pwsh that hosts the WebView2 pet window and tails .helix/hook-events.jsonl.
//
// Designed to never block or fail the hook chain: any error is logged to
// helix/pet/pet-host.log and the script exits 0.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const { getRepoRoot } = require('./helix-runtime');

function petPaths(repoRoot) {
  // repoRoot = helix repo root (parent of .github/hooks). Pet lives under pet/.
  const petDir = path.join(repoRoot, 'pet');
  return {
    petDir,
    hostScript: path.join(petDir, 'pet-host.ps1'),
    pidFile: path.join(petDir, 'pet-host.pid'),
    logFile: path.join(petDir, 'pet-host.log'),
  };
}

function logSpawn(logFile, message) {
  try {
    fs.mkdirSync(path.dirname(logFile), { recursive: true });
    fs.appendFileSync(
      logFile,
      `[${new Date().toISOString()}] [pet-spawn] ${message}\n`,
      'utf8',
    );
  } catch {
    // Logging is best-effort.
  }
}

function isProcessAlive(pid) {
  if (!Number.isFinite(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    // EPERM means the process exists but we can't signal it — still alive.
    return err && err.code === 'EPERM';
  }
}

function main() {
  let repoRoot;
  try {
    repoRoot = getRepoRoot();
  } catch (err) {
    // Hook context resolution failed; bail silently.
    return;
  }

  const { petDir, hostScript, pidFile, logFile } = petPaths(repoRoot);

  // Idempotency: if a live PID is recorded, do nothing.
  if (fs.existsSync(pidFile)) {
    const raw = fs.readFileSync(pidFile, 'utf8').trim();
    const pid = Number.parseInt(raw, 10);
    if (isProcessAlive(pid)) {
      logSpawn(logFile, `Pet host already running (PID ${pid})`);
      return;
    }
    logSpawn(logFile, `Stale PID file (${raw}); removing and respawning`);
    try { fs.unlinkSync(pidFile); } catch { /* best-effort */ }
  }

  if (!fs.existsSync(hostScript)) {
    logSpawn(logFile, `Host script missing: ${hostScript}; skipping spawn`);
    return;
  }

  // Launch a detached hidden pwsh process. The host writes its own PID file.
  const child = spawn(
    'pwsh',
    ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
     '-File', hostScript],
    {
      cwd: petDir,
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    },
  );

  child.on('error', (err) => {
    logSpawn(logFile, `Failed to spawn pet host: ${err.message}`);
  });
  child.unref();
  logSpawn(logFile, `Spawned pet host (child PID ${child.pid})`);
}

try {
  main();
} catch (err) {
  // Hooks must not fail the session.
  try {
    const { logFile } = petPaths(getRepoRoot());
    logSpawn(logFile, `Fatal: ${err && err.message}`);
  } catch {
    // give up
  }
}
