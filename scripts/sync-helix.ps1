[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$installStatePath = Join-Path $TargetRoot '.helix/install-state.yml'

if (-not (Test-Path $installStatePath)) {
    throw "No .helix/install-state.yml found in '$TargetRoot'. Run install-helix.ps1 first."
}

$installState = Import-HelixYamlFile -Path $installStatePath
$kind = $installState.helix_core.kind
if ($kind -ne 'local-path') {
    throw "sync-helix.ps1 currently supports only helix_core.kind=local-path."
}

$source = [string]$installState.helix_core.source
$sourceRoot = if ([System.IO.Path]::IsPathRooted($source)) {
    $source
} else {
    Join-Path $TargetRoot $source
}

if (-not (Test-Path $sourceRoot)) {
    throw "Helix core source path '$sourceRoot' does not exist."
}

& (Join-Path $PSScriptRoot 'install-helix.ps1') -TargetRoot $TargetRoot -SourceRoot $sourceRoot -Version ([string]$installState.helix_core.version) -Force:$Force
