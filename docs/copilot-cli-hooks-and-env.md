# Copilot CLI Hooks and Environment

Operational reference for using GitHub Copilot CLI hooks and environment variables from Helix.

Source baseline: GitHub Copilot CLI [`changelog.md`](https://github.com/github/copilot-cli/raw/refs/heads/main/changelog.md) through `1.0.39 - 2026-04-28`.

This is changelog-derived, not a replacement for live CLI help. When wiring production hooks, verify the currently installed CLI with `/env`, `--print-debug-info`, and any available `copilot help` topics.

## Helix Defaults

Helix should treat Copilot hooks as cheap integration points:

- Hooks may record telemetry, enforce local policy, refresh context, or derive traces.
- Hooks should not become the canonical session recorder. Copilot owns raw session history.
- Hook failures should be non-fatal unless the hook is explicitly a permission gate.
- Operational hook records belong in `.helix/hook-events.jsonl`; lifecycle state belongs in `.helix/state-deltas.jsonl`.

Current Helix hook config lives at `.github/hooks/helix.json` and uses:

| Event | Current Helix use |
|---|---|
| `sessionStart` | append baseline workspace/session state |
| `preToolUse` | audit or block risky tool use before execution |
| `agentStop` | refresh CRG context after agent completion |
| `subagentStop` | refresh CRG context after subagent completion |
| `sessionEnd` | derive traces, trigger distillation, refresh CRG context |

## Hook Config Basics

Known config locations from the changelog:

- Repo hooks: `.github/hooks/`
- Personal hooks: `~/.copilot/hooks`
- Settings-backed hooks: `settings.json`, `settings.local.json`, and `config.json`
- Repository settings moved from `.github/copilot/config.json` to `.github/copilot/settings.json`

Compatibility notes:

- Hook event names accept camelCase and PascalCase.
- Hook payloads use VS Code-compatible snake_case fields such as `hook_event_name`, `session_id`, and ISO 8601 timestamps.
- Hook config files may omit `version`.
- Hook config supports `disableAllHooks`.
- Hook commands can use platform-specific `bash` / `powershell`, or `command` as a cross-platform alias.
- `timeout` is accepted as an alias for `timeoutSec`.
- Claude Code nested `matcher` / `hooks` structures and optional `type` fields are supported.
- `preToolUse.matcher` runs only when the tool name fully matches the regex.
- Hooks can run local commands or POST JSON payloads to an HTTP endpoint.

Flat command hook shape used by Helix:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "type": "command",
        "command": "node .github/hooks/scripts/session-start.js",
        "cwd": ".",
        "timeoutSec": 10
      }
    ]
  }
}
```

HTTP hook concept:

```json
{
  "version": 1,
  "hooks": {
    "notification": [
      {
        "type": "http",
        "url": "http://127.0.0.1:8787/copilot-hook",
        "timeoutSec": 5
      }
    ]
  }
}
```

Use HTTP hooks only for local, trusted endpoints unless there is a clear reason to send hook payloads elsewhere.

## Available Hook Events

These are the hook events explicitly named in the changelog.

| Hook | What It Is | Helix Use Cases |
|---|---|---|
| `sessionStart` | Fires when a session starts. `additionalContext` from this hook can be injected into the conversation. In interactive mode, it fires once per session. | Record active workspace, workflow, phase, CRG mode, and model context. Inject a terse "active Helix workspace" note. |
| startup prompt hooks | Startup hook facility that can auto-submit prompts or slash commands when a session starts. | Start with a Helix status prompt, run `/env`, or trigger a workspace readiness check. Keep this opt-in to avoid surprise automation. |
| `preToolUse` | Runs before a tool executes. It can deny execution, modify arguments, update input, add context, or set permission decisions. | Block destructive shell commands, route edits to allowed paths, attach CRG preflight context, or audit high-risk tools. |
| `PermissionRequest` | Allows scripts to approve or deny tool permission requests. | Centralize policy decisions such as "allow tests in repo roots" or "deny writes outside attached repos." |
| `postToolUse` | Runs after successful tool calls. Since `1.0.15`, it runs only after success. | Refresh local indexes after edits, append success telemetry, or update task progress. |
| `postToolUseFailure` | Runs when tool execution errors. | Record failed commands, detect repeated failures, or trigger a recovery hint without polluting lifecycle state. |
| `notification` | Asynchronous event for shell completion, permission prompts, elicitation dialogs, and agent completion. Permission prompt notifications fire only when a prompt is actually shown. | Send desktop or chat notifications, record long-running task completion, or observe human-gated pauses. |
| `subagentStart` | Fires when a subagent is spawned and can inject additional context into the subagent prompt. | Pass slice ownership, execution-plan contract, CRG bundle path, and write-path constraints to subagents. |
| `agentStop` | Fires when the main agent reaches completion; introduced to control agent completion. | Run final context refresh, check `done_when`, or require review/distillation gates. |
| `subagentStop` | Fires when a subagent reaches completion; introduced with `agentStop`. | Collect subagent result metadata, run CRG sweep, and update task status. |
| `sessionEnd` | Fires when a session ends. In interactive mode, it fires once per session. | Derive Copilot traces, write session-index rows, trigger distillation checks, and flush hook telemetry. |
| `preCompact` | Runs before context compaction starts. | Persist a compact checkpoint, snapshot active task state, or add a "what must survive compaction" marker. |

### Hook Examples

Block risky shell usage before it reaches the tool:

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "command": "node .github/hooks/scripts/pre-tool-use.js",
        "cwd": ".",
        "timeoutSec": 10,
        "matcher": "^(Bash|bash|shell)$"
      }
    ]
  }
}
```

Run Helix trace derivation at session end:

```json
{
  "version": 1,
  "hooks": {
    "sessionEnd": [
      {
        "type": "command",
        "command": "node .github/hooks/scripts/derive-trace.js",
        "cwd": ".github/hooks",
        "timeoutSec": 30
      }
    ]
  }
}
```

Inject task context into spawned subagents:

```json
{
  "version": 1,
  "hooks": {
    "subagentStart": [
      {
        "type": "command",
        "command": "node .github/hooks/scripts/subagent-context.js",
        "cwd": ".",
        "timeoutSec": 5
      }
    ]
  }
}
```

A `subagentStart` script can return a small `additionalContext` payload containing the execution-plan path, allowed write paths, and relevant context bundle.

## Environment Variables

These variables are named in the changelog. Some are active configuration surfaces; others are compatibility or historical toggles. Prefer the `COPILOT_*` names when both Copilot-specific and generic alternatives exist.

### Authentication And Hosts

| Variable | What It Does | How To Use |
|---|---|---|
| `COPILOT_GITHUB_TOKEN` | Authenticates Copilot CLI from an environment token. Takes precedence over `GH_TOKEN`. | Set in CI or a secure local shell when OAuth is not appropriate. |
| `GH_TOKEN` | Generic GitHub token fallback for auth flows. | Use only when you cannot use `COPILOT_GITHUB_TOKEN`. |
| `GITHUB_TOKEN` | Available inside agent shell sessions. Also commonly referenced by MCP server env mappings. | Use for GitHub API calls inside shell or MCP processes when already provided by CI. |
| `GITHUB_ASKPASS` | Supported for authentication. | Point to an askpass helper when non-interactive credential prompts are needed. |
| `COPILOT_GH_HOST` | Sets the GitHub hostname for Copilot CLI and takes precedence over `GH_HOST`. | Use for GitHub Enterprise Cloud or enterprise hosts. |
| `GH_HOST` | Generic GitHub host used for non-interactive GHE logins and as a lower-precedence host input. | Keep as a fallback if other GitHub tools also depend on it. |

PowerShell example:

```powershell
$env:COPILOT_GH_HOST = "github.example.com"
$env:COPILOT_GITHUB_TOKEN = "<token>"
copilot
```

### Session And Runtime

| Variable | What It Does | How To Use |
|---|---|---|
| `COPILOT_AGENT_SESSION_ID` | Passed to shell commands and MCP servers. | Include it in logs so Helix can correlate hook events, shell commands, MCP activity, and trace records. |
| `COPILOT_CLI` | Set to `1` for Copilot CLI subprocesses so Git hooks can detect them. | Skip interactive Git hook prompts when Copilot runs commands. |
| `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | Points Copilot CLI at custom instruction file directories. | Use for explicit instruction discovery when repo defaults are not enough. |
| `MULTI_TURN_AGENTS` | Feature-mode environment mentioned for sync task behavior; sync calls block instead of auto-promoting after 60 seconds. | Treat as advanced/compat behavior, not a Helix default. |

Git hook example:

```sh
if [ "$COPILOT_CLI" = "1" ]; then
  exit 0
fi
```

### Plugin And Hook Context

| Variable | What It Does | How To Use |
|---|---|---|
| `PLUGIN_ROOT` | Plugin hook install directory. | Resolve files shipped with a plugin hook. |
| `COPILOT_PLUGIN_ROOT` | Copilot-specific plugin root. | Prefer this when writing Copilot-native plugin hooks. |
| `CLAUDE_PLUGIN_ROOT` | Claude-compatible plugin root. | Use only for cross-host plugin compatibility. |
| `CLAUDE_PROJECT_DIR` | Project directory for plugin hooks. | Compatibility input for hooks shared with Claude-style configs. |
| `CLAUDE_PLUGIN_DATA` | Plugin data directory. | Store plugin-local data when sharing hooks across hosts. |

Hook config templates can also use `{{project_dir}}` and `{{plugin_data_dir}}`.

### Terminal And UI

| Variable | What It Does | How To Use |
|---|---|---|
| `SHELL` | Shell escape commands (`!`) use this instead of always invoking `/bin/sh`. | Set to your preferred shell before launching Copilot. |
| `BROWSER` | Browser command; Copilot splits this value on spaces. | Set when browser launching needs a specific command. |
| `COPILOT_DISABLE_TERMINAL_TITLE` | Opts out of terminal title updates. | Set to `1` when terminal title changes conflict with your shell or IDE. |
| `COPILOT_KITTY` | Historical Kitty keyboard protocol toggle from early multi-line input support. | Verify current behavior before using; later changelog entries made Kitty protocol more broadly enabled. |
| `NO_COLOR` | Disables color output where supported. | Set for plain logs, CI output, or accessibility needs. |
| `TEMP` | Used as fallback output location for feedback bundles when cwd is not writable. | Ensure it points to a writable location in locked-down environments. |
| `XDG_STATE_HOME` | Copilot moved auto-update package storage to `~/.copilot/pkg` instead of relying on this. | Do not use it to control Copilot package storage. |

PowerShell example:

```powershell
$env:COPILOT_DISABLE_TERMINAL_TITLE = "1"
$env:NO_COLOR = "1"
copilot
```

### Network And Proxy

| Variable | What It Does | How To Use |
|---|---|---|
| `HTTPS_PROXY` | Configures HTTPS proxy support. | Set for corporate network egress. |
| `HTTP_PROXY` | Configures HTTP proxy support. | Set alongside `HTTPS_PROXY` when required by your environment. |
| `NO_PROXY` | Excludes hosts from proxy routing. | Add localhost, internal domains, and local MCP endpoints. |

PowerShell example:

```powershell
$env:HTTPS_PROXY = "http://proxy.example.com:8080"
$env:HTTP_PROXY = "http://proxy.example.com:8080"
$env:NO_PROXY = "localhost,127.0.0.1,.internal.example.com"
copilot
```

### CI And MCP

| Variable | What It Does | How To Use |
|---|---|---|
| `GITHUB_WORKSPACE` | In GitHub Actions, MCP servers automatically use it as their working directory. | Set by Actions; use it to keep MCP cwd aligned with the checkout. |
| `GITHUB_ACCESS_TOKEN` | Example MCP process variable. Values in MCP `env` blocks are literal unless wrapped as an environment reference. | Map it from `${GITHUB_TOKEN}` or another source token. |

MCP env mapping example:

```json
{
  "env": {
    "GITHUB_ACCESS_TOKEN": "${GITHUB_TOKEN}"
  }
}
```

Without `${...}`, the value is treated literally:

```json
{
  "env": {
    "GITHUB_ACCESS_TOKEN": "GITHUB_TOKEN"
  }
}
```

## Helix Recommendations

- Keep Helix hook scripts idempotent and bounded by short timeouts.
- Prefer `sessionStart`, `preToolUse`, `agentStop`, `subagentStop`, and `sessionEnd` for Helix core wiring.
- Use `notification`, `postToolUse`, and `postToolUseFailure` for observability, not lifecycle control.
- Use `PermissionRequest` only when Helix is ready to make deterministic allow/deny decisions.
- Use `subagentStart` only when the execution plan has clear ownership, allowed write paths, and done criteria.
- Prefer `COPILOT_AGENT_SESSION_ID` as the correlation key across hook logs and shell/MCP activity.
- Keep environment-sensitive behavior documented in workspace artifacts so autonomous agents do not infer policy from hidden local shell state.
