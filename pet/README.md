# Helix Floating Pet

A small always-on-top companion window — visually inspired by OpenAI Codex's
desktop pet — that visualizes which Helix agent is currently active, what tool
it's running, and whether the latest run passed or needs review.

```
+-----------------------+
| ● Tool                |
|                       |
|       (pet)           |
|                       |
| Running bash          |
+-----------------------+
```

## How it works

```
Copilot session ─fires hooks─▶ helix-runtime appends to .helix/hook-events.jsonl
                                            │
                                            ▼
                              pet-host.ps1 (long-running)
                                tails the JSONL file,
                                maps event_type → pet state,
                                ExecuteScriptAsync(window.setPetState(...))
                                            │
                                            ▼
                          WebView2 inside a borderless WPF window
                                hosting helix/pet/content/index.html
```

Pet states reuse the prototype's vocabulary
(`idle`, `thinking`, `tool`, `pass`, `fail` — see [content/main.js](content/main.js)).
Mapping from hook events:

| `event_type` | Pet state | Bubble                         |
| ------------ | --------- | ------------------------------ |
| sessionStart | idle      | "Session started"              |
| preToolUse   | tool      | "Running `<tool>`"             |
| agentStop ✓  | pass      | "`<agent>` done"               |
| agentStop ✗  | fail      | "Review needed: `<agent>`"     |
| subagentStop | thinking  | "Subagent: `<name>`"           |
| sessionEnd   | idle      | "Session ended"                |

## Lifecycle

The pet auto-spawns on Copilot `sessionStart` via
[`.github/hooks/scripts/pet-spawn.js`](../.github/hooks/scripts/pet-spawn.js),
which is wired into [`helix.json`](../.github/hooks/helix.json) alongside the
existing `session-start.js` baseline emitter.

The spawner is idempotent: if `pet-host.pid` points to a live process, it
exits silently. Otherwise it launches a hidden `pwsh` running `pet-host.ps1`.

The host stays up across sessions and returns to `idle` when a session ends.
Close the window manually to terminate it.

## Manual controls

```powershell
# Wake the pet (if not already running):
node helix/.github/hooks/scripts/pet-spawn.js

# Tuck it away — close the window, or:
Stop-Process -Id (Get-Content helix/pet/pet-host.pid)

# Demo mode (cycle through all states without needing a Copilot session):
pwsh -NoProfile -File helix/pet/pet-host.ps1 -Demo
```

## First-run bootstrap

`pet-host.ps1` requires the WebView2 managed assemblies. On first launch it
downloads `Microsoft.Web.WebView2` from NuGet and caches three DLLs in
`helix/pet/lib/` (gitignored). The WebView2 runtime itself ships with Windows 11.

If you'd rather pre-populate `lib/` instead of letting the host fetch it, drop
these three files in:

- `Microsoft.Web.WebView2.Core.dll`
- `Microsoft.Web.WebView2.Wpf.dll`
- `WebView2Loader.dll`

## Testing without Copilot

Append a synthetic event to drive the bridge:

```powershell
$evt = @{
  schema_version = 1
  ts = (Get-Date -Format o)
  event_type = 'preToolUse'
  hook_name = 'bash'
} | ConvertTo-Json -Compress
Add-Content -LiteralPath .helix/hook-events.jsonl -Value $evt
```

The pet should switch to the `tool` state within ~300 ms.

## Browser preview of the static surface

```
helix/prototypes/copilot-pet-webview/content/index.html       # full prototype with state-picker + demo loop
helix/pet/content/index.html?demo=1                           # production HTML, demo loop on
helix/pet/content/index.html                                  # production HTML, idle until told otherwise
```

The prototype copy retains the bottom state-picker buttons and starts the
demo loop only when `?demo=1` is present in the URL — otherwise it sits idle
waiting for `window.setPetState(...)` calls from the host.

## v1 limitations

- **Windows-only** (WebView2 + WPF). macOS/Linux hosts would need a separate
  Tauri/Electron-style wrapper; the page contract is portable.
- **Opaque borderless window**, not a free-form transparent shape. WebView2
  has known issues with WPF `AllowsTransparency=true`; we use a small
  rectangular floating window instead. Same UX otherwise (always-on-top,
  draggable from anywhere, no taskbar entry).
- **Single pet**. Even in `fleet` mode, one pet reflects whichever role is
  currently active; the bubble carries the role name.
- **No sprite atlas yet** — pet visuals are pure CSS. To swap in a
  Codex-style 8×9 WebP atlas later, run OpenAI's `$hatch-pet` skill in a
  Codex session and adapt `content/style.css` to use `background-position`.
