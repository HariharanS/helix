[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [switch]$WriteRepoState
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$issues = @()
$warnings = @()

function Add-Issue([string]$Message) {
    $script:issues += $Message
}

function Add-WarningLine([string]$Message) {
    $script:warnings += $Message
}

$installStatePath = Join-Path $TargetRoot '.helix/install-state.yml'
if (-not (Test-Path $installStatePath)) {
    Add-Issue "Missing .helix/install-state.yml"
}

$activeWorkspacePath = Get-HelixActiveWorkspacePath -HelixRoot $TargetRoot
if (-not (Test-Path $activeWorkspacePath)) {
    Add-WarningLine "Missing active workspace pointer (.helix/active-workspace.yml)"
}

$registryPath = Join-Path $TargetRoot 'repos.yml'
$repoIndex = @{}
if (-not (Test-Path $registryPath)) {
    Add-Issue "Missing repos.yml"
} else {
    $registry = Import-HelixYamlFile -Path $registryPath
    $seenIds = @{}
    $seenPaths = @{}

    foreach ($repo in $registry.repos) {
        $repoId = [string]$repo.id
        $localPath = [string]$repo.local_path

        if ($seenIds.ContainsKey($repoId)) {
            Add-Issue "Duplicate repo id '$repoId' in repos.yml"
        } else {
            $seenIds[$repoId] = $true
        }

        if ($seenPaths.ContainsKey($localPath)) {
            Add-Issue "Duplicate repo local_path '$localPath' in repos.yml"
        } else {
            $seenPaths[$localPath] = $true
        }

        $repoIndex[$repoId] = $repo

        $repoRoot = Join-Path $TargetRoot $localPath
        $repoState = Get-HelixRepoReadiness -RepoId $repoId -RepoPath $repoRoot
        if ($WriteRepoState) {
            Write-HelixYamlFile -Path (Join-Path $TargetRoot ".helix/repo-state/$repoId.yml") -Value $repoState
        }

        if ($repoState.readiness.state -eq 'needs-onboarding') {
            Add-WarningLine "Repo '$repoId' needs onboarding."
        }
    }
}

$workspacesRoot = Join-Path $TargetRoot 'workspaces'
if (Test-Path $workspacesRoot) {
    Get-ChildItem -Path $workspacesRoot -Directory | ForEach-Object {
        $workspaceFile = Join-Path $_.FullName 'workspace.yml'
        if (-not (Test-Path $workspaceFile)) {
            return
        }

        $workspace = Import-HelixYamlFile -Path $workspaceFile
        foreach ($workspaceRepo in $workspace.repos) {
            $repoId = [string]$workspaceRepo.repo_id
            if (-not $repoIndex.ContainsKey($repoId)) {
                Add-Issue "Workspace '$($_.Name)' references unknown repo_id '$repoId'."
            }
        }

        foreach ($artifactKey in @('refined_intent', 'prd', 'tech_design')) {
            if ($workspace.artifacts.Contains($artifactKey) -and $workspace.artifacts[$artifactKey]) {
                $artifactPath = Join-Path $_.FullName ([string]$workspace.artifacts[$artifactKey])
                if (-not (Test-Path $artifactPath)) {
                    Add-WarningLine "Workspace '$($_.Name)' artifact '$artifactKey' points to missing path '$artifactPath'."
                }
            }
        }
    }
}

Write-Host "Helix doctor: $TargetRoot"
if ($issues.Count -gt 0) {
    Write-Host ''
    Write-Host 'Issues:'
    $issues | ForEach-Object { Write-Host " - $_" }
}

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:'
    $warnings | ForEach-Object { Write-Host " - $_" }
}

if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host 'No issues found.'
}

if ($issues.Count -gt 0) {
    exit 1
}
