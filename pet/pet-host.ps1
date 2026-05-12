#requires -Version 7.0
<#
.SYNOPSIS
  Helix floating pet host. Loads the prototype HTML in a WebView2/WPF window
  and bridges Helix hook events (.helix/hook-events.jsonl) into setPetState()
  calls inside the page.

.DESCRIPTION
  Spawned by .github/hooks/scripts/pet-spawn.js on Copilot sessionStart, or
  manually for development. Writes its PID to helix/pet/pet-host.pid and
  removes it on close. Logs to helix/pet/pet-host.log.
#>

param(
  [switch]$Demo
)

$ErrorActionPreference = 'Stop'
$petRoot     = $PSScriptRoot
$libDir      = Join-Path $petRoot 'lib'
$logFile     = Join-Path $petRoot 'pet-host.log'
$pidFile     = Join-Path $petRoot 'pet-host.pid'
$contentIdx  = Join-Path $petRoot 'content\index.html'

function Write-PetLog {
  param([string]$Message)
  $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
  Add-Content -LiteralPath $logFile -Value $line
}

function Initialize-WebView2 {
  param([string]$LibDir)
  $version = '1.0.2792.45'
  $url = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$version"
  $tmpZip  = Join-Path ([System.IO.Path]::GetTempPath()) "wv2-$version.zip"
  $tmpDir  = Join-Path ([System.IO.Path]::GetTempPath()) "wv2-$version"
  Write-PetLog "Downloading Microsoft.Web.WebView2 $version from NuGet"
  Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
  if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
  Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
  New-Item -ItemType Directory -Path $LibDir -Force | Out-Null

  # Pick managed DLLs: PowerShell 7 is on .NET 5+/Core, prefer netcoreapp/net6+
  # over net462. Sort-Object Expression scriptblocks receive the item via $_.
  function Find-ManagedDll {
    param([string]$Name, [string]$Root)
    $candidates = Get-ChildItem -LiteralPath $Root -Filter $Name -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.FullName -notmatch '\\native(_uap)?\\' }
    if (-not $candidates) { throw "Could not find $Name under $Root" }
    $ranked = $candidates | Sort-Object @{ Expression = {
      $f = $_.FullName
      if     ($f -match '\\net[5-9]\.')   { 1 }
      elseif ($f -match '\\netcoreapp')   { 2 }
      elseif ($f -match '\\netstandard')  { 3 }
      elseif ($f -match '\\net4')         { 4 }
      else                                { 5 }
    } }
    ($ranked | Select-Object -First 1).FullName
  }

  $coreDll = Find-ManagedDll -Name 'Microsoft.Web.WebView2.Core.dll' -Root $tmpDir
  $wpfDll  = Find-ManagedDll -Name 'Microsoft.Web.WebView2.Wpf.dll'  -Root $tmpDir
  $loader  = Join-Path $tmpDir 'runtimes\win-x64\native\WebView2Loader.dll'
  if (-not (Test-Path $loader)) {
    $loader = (Get-ChildItem -LiteralPath $tmpDir -Filter 'WebView2Loader.dll' -Recurse -File |
               Where-Object { $_.FullName -match 'win-x64' } |
               Select-Object -First 1).FullName
  }
  if (-not $loader) { throw "Could not locate win-x64 WebView2Loader.dll under $tmpDir" }

  Write-PetLog "Using managed core: $coreDll"
  Write-PetLog "Using managed wpf:  $wpfDll"
  Write-PetLog "Using native loader: $loader"

  Copy-Item -LiteralPath $coreDll -Destination $LibDir -Force
  Copy-Item -LiteralPath $wpfDll  -Destination $LibDir -Force
  Copy-Item -LiteralPath $loader  -Destination $LibDir -Force
  Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Bootstrap WebView2 if missing ---------------------------------------
$wv2Wpf    = Join-Path $libDir 'Microsoft.Web.WebView2.Wpf.dll'
$wv2Core   = Join-Path $libDir 'Microsoft.Web.WebView2.Core.dll'
$wv2Loader = Join-Path $libDir 'WebView2Loader.dll'

if (-not (Test-Path $wv2Wpf) -or -not (Test-Path $wv2Core) -or -not (Test-Path $wv2Loader)) {
  Initialize-WebView2 -LibDir $libDir
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
[System.Reflection.Assembly]::LoadFrom($wv2Core) | Out-Null
[System.Reflection.Assembly]::LoadFrom($wv2Wpf)  | Out-Null

# --- Resolve repo root and events file -----------------------------------
# $petRoot = helix/pet -> $repoRoot = helix (parent), where .helix/ lives.
$repoRoot   = (Resolve-Path (Join-Path $petRoot '..')).Path
$eventsPath = Join-Path $repoRoot '.helix\hook-events.jsonl'

if (-not (Test-Path (Split-Path $eventsPath))) {
  New-Item -ItemType Directory -Path (Split-Path $eventsPath) -Force | Out-Null
}
if (-not (Test-Path $eventsPath)) {
  New-Item -ItemType File -Path $eventsPath -Force | Out-Null
}

# --- Write PID file ------------------------------------------------------
[System.IO.File]::WriteAllText($pidFile, $PID.ToString())
Write-PetLog "Pet host starting (PID $PID); tailing $eventsPath"

# --- Build the WPF window -----------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:wv2="clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf"
        Title="Loopi"
        Width="228" Height="264"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="False"
        WindowStartupLocation="Manual"
        Background="#0A0E16">
  <Grid>
    <wv2:WebView2 x:Name="Web"/>
  </Grid>
</Window>
'@

$reader    = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader $xaml))
$window    = [System.Windows.Markup.XamlReader]::Load($reader)
$web       = $window.FindName('Web')

# Bottom-right of primary working area, with a small margin.
$workArea     = [System.Windows.SystemParameters]::WorkArea
$window.Left  = $workArea.Right  - 228 - 24
$window.Top   = $workArea.Bottom - 264 - 24

# Drag from anywhere: WebView2 captures mouse events, so the page forwards
# mousedown via chrome.webview.postMessage('drag') and we DragMove from there.
# (See WebMessageReceived handler below.)

# --- Pet state machine --------------------------------------------------
function Get-PetState {
  param($evt)
  if ($null -eq $evt) { return $null }
  switch ($evt.event_type) {
    'sessionStart' { return @{ state = 'idle';     message = 'Session started' } }
    'preToolUse'   {
      $tool = $evt.tool_name
      if (-not $tool) { $tool = $evt.hook_name }
      if (-not $tool) { $tool = 'tool' }
      return @{ state = 'tool'; message = "Running $tool" }
    }
    'agentStop'    {
      $exit = 0
      if ($null -ne $evt.exit_code) { $exit = [int]$evt.exit_code }
      $agent = $evt.hook_name; if (-not $agent) { $agent = 'agent' }
      if ($exit -eq 0) { return @{ state = 'pass'; message = "$agent done" } }
      else             { return @{ state = 'fail'; message = "Review needed: $agent" } }
    }
    'subagentStop' {
      $name = $evt.hook_name; if (-not $name) { $name = 'subagent' }
      return @{ state = 'thinking'; message = "Subagent: $name" }
    }
    'sessionEnd'   { return @{ state = 'idle'; message = 'Session ended' } }
    default        { return $null }
  }
}

function Push-State {
  param($petState)
  if ($null -eq $petState) { return }
  $s = ($petState.state   -replace "'", "\\'") -replace "[\r\n]", ' '
  $m = ($petState.message -replace "'", "\\'") -replace "[\r\n]", ' '
  $script = "window.setPetState('$s','$m')"
  try { $null = $web.CoreWebView2.ExecuteScriptAsync($script) }
  catch { Write-PetLog ("ExecuteScriptAsync error: " + $_.Exception.Message) }
}

# --- WebView2 init + JSONL tail timer -----------------------------------
$tailState = @{ position = 0L; ready = $false }

$web.add_CoreWebView2InitializationCompleted({
  param($s,$e)
  if (-not $e.IsSuccess) {
    Write-PetLog ("CoreWebView2 init failed: " + $e.InitializationException)
    return
  }
  $tailState.ready = $true
  $uri = ([System.Uri]::new($contentIdx)).AbsoluteUri
  Write-PetLog "Navigating to $uri"
  $web.CoreWebView2.Navigate($uri)
  # Seek to end so we don't replay every historical event.
  if (Test-Path $eventsPath) {
    $tailState.position = (Get-Item $eventsPath).Length
  }
  # Drag-from-anywhere: page posts 'drag' on mousedown, we call DragMove on the UI thread.
  $web.CoreWebView2.add_WebMessageReceived({
    param($s2,$e2)
    $msg = $null
    try { $msg = $e2.TryGetWebMessageAsString() } catch {}
    if ($msg -eq 'drag') {
      $window.Dispatcher.BeginInvoke([Action]{ try { $window.DragMove() } catch {} }) | Out-Null
    }
  })
})

# WebView2 needs a writable user-data folder; default location (next to pwsh.exe)
# is read-only for non-admin users.
$userDataFolder = Join-Path $env:LOCALAPPDATA 'Helix\Pet\WebView2'
New-Item -ItemType Directory -Path $userDataFolder -Force | Out-Null
$creationProps = New-Object Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
$creationProps.UserDataFolder = $userDataFolder
$web.CreationProperties = $creationProps
Write-PetLog "WebView2 user data folder: $userDataFolder"

# EnsureCoreWebView2Async needs the Dispatcher loop running; defer until Loaded.
$window.add_Loaded({
  try { $null = $web.EnsureCoreWebView2Async($null) }
  catch { Write-PetLog ("EnsureCoreWebView2Async failed: " + $_.Exception.Message) }
})

# Demo mode: cycle states without reading JSONL.
if ($Demo.IsPresent) {
  $demoStates = @('idle','thinking','tool','pass','fail','idle')
  $idx = 0
  $demoTimer = New-Object System.Windows.Threading.DispatcherTimer
  $demoTimer.Interval = [TimeSpan]::FromSeconds(2)
  $demoTimer.Add_Tick({
    if (-not $tailState.ready) { return }
    Push-State @{ state = $demoStates[$idx]; message = "demo: " + $demoStates[$idx] }
    $script:idx = (($idx + 1) % $demoStates.Length)
  }.GetNewClosure())
  $demoTimer.Start()
}

$tailTimer = New-Object System.Windows.Threading.DispatcherTimer
$tailTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$tailTimer.Add_Tick({
  if (-not $tailState.ready) { return }
  if (-not (Test-Path $eventsPath)) { return }
  $fi = Get-Item $eventsPath
  if ($fi.Length -lt $tailState.position) { $tailState.position = 0 }    # truncated
  if ($fi.Length -eq $tailState.position) { return }                      # no new bytes

  $fs = [System.IO.File]::Open($eventsPath, 'Open', 'Read', 'ReadWrite')
  try {
    $fs.Position = $tailState.position
    $sr = New-Object System.IO.StreamReader $fs
    while (-not $sr.EndOfStream) {
      $line = $sr.ReadLine()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $evt = $line | ConvertFrom-Json
        $petState = Get-PetState $evt
        Push-State $petState
      } catch {
        Write-PetLog ("Parse/dispatch error: " + $_.Exception.Message + " :: " + $line)
      }
    }
    $tailState.position = $fs.Position
  } finally {
    $fs.Dispose()
  }
})
$tailTimer.Start()

# --- Cleanup on close ---------------------------------------------------
$window.Add_Closed({
  $tailTimer.Stop()
  if (Test-Path $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
  Write-PetLog "Pet host closed"
})

[void]$window.ShowDialog()
