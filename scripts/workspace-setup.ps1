[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Workspace,
    [string]$TargetRoot = (Get-Location).Path,
    [switch]$CloneMissing,
    [switch]$FetchExisting,
    [string]$ReposCsv,
    [string]$DisplayName,
    [string]$Description,
    [string]$Objective,
    [switch]$IncludeClaudeSettings,
    [switch]$SkipClaudeSettings,
    [switch]$SkipGraphBuild
)

$setupParams = @{
    Workspace = $Workspace
    TargetRoot = $TargetRoot
}

if ($CloneMissing) { $setupParams.CloneMissing = $true }
if ($FetchExisting) { $setupParams.FetchExisting = $true }
if (-not [string]::IsNullOrWhiteSpace($ReposCsv)) { $setupParams.ReposCsv = $ReposCsv }
if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $setupParams.DisplayName = $DisplayName }
if (-not [string]::IsNullOrWhiteSpace($Description)) { $setupParams.Description = $Description }
if (-not [string]::IsNullOrWhiteSpace($Objective)) { $setupParams.Objective = $Objective }
if ($IncludeClaudeSettings) { $setupParams.IncludeClaudeSettings = $true }
if ($SkipClaudeSettings) { $setupParams.SkipClaudeSettings = $true }
if ($SkipGraphBuild) { $setupParams.SkipGraphBuild = $true }

& (Join-Path $PSScriptRoot 'setup-workspace.ps1') @setupParams
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
