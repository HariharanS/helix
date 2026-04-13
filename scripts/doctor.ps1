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

$agentDir = Join-Path $TargetRoot '.github/agents'
if (Test-Path $agentDir) {
    Get-ChildItem -Path $agentDir -Filter '*.agent.md' -File | ForEach-Object {
        $frontmatterHead = Get-Content -LiteralPath $_.FullName -TotalCount 12
        if ($frontmatterHead -match '^model:\s*\[') {
            Add-Issue "Agent '$($_.Name)' has malformed custom agent frontmatter: 'model' must be a string, not an array."
        }
    }
}

$agentTemplatePath = Join-Path $TargetRoot 'templates/agent.agent.md.template'
if (Test-Path $agentTemplatePath) {
    $templateHead = Get-Content -LiteralPath $agentTemplatePath -TotalCount 12
    if ($templateHead -match '^model:\s*\[') {
        Add-Issue "Template 'templates/agent.agent.md.template' uses malformed custom agent frontmatter: 'model' must be a string, not an array."
    }
}

$mcpPath = Join-Path $TargetRoot '.mcp.json'
if (Test-Path $mcpPath) {
    try {
        $mcpConfig = Get-Content -LiteralPath $mcpPath -Raw | ConvertFrom-Json
        $hasCodeReviewGraph = $null -ne $mcpConfig.mcpServers -and ($mcpConfig.mcpServers.PSObject.Properties.Name -contains 'code-review-graph')
        if ($hasCodeReviewGraph) {
            $runtimeAvailable = (Get-Command uvx -ErrorAction SilentlyContinue) -or (Get-Command code-review-graph -ErrorAction SilentlyContinue)
            if (-not $runtimeAvailable) {
                Add-WarningLine "'.mcp.json' enables 'code-review-graph', but no 'uvx' or 'code-review-graph' executable was found in PATH. Copilot will fall back to manual context when the MCP server cannot start."
            }
        }
    } catch {
        Add-Issue "Invalid JSON in '.mcp.json'."
    }
}

$installStatePath = Join-Path $TargetRoot '.helix/install-state.yml'
$registryPath = Join-Path $TargetRoot 'repos.yml'
$hasInstallState = Test-Path $installStatePath
$hasRegistry = Test-Path $registryPath

if (-not $hasInstallState -and -not $hasRegistry) {
    Add-WarningLine "Helix instance state is not bootstrapped in '$TargetRoot'. Missing '.helix/install-state.yml' and 'repos.yml'. Run install-helix.ps1 in a target meta repo before using doctor for instance validation."
} else {
    if (-not $hasInstallState) {
        Add-Issue "Missing .helix/install-state.yml"
    }

    if (-not $hasRegistry) {
        Add-Issue "Missing repos.yml"
    }
}

$activeWorkspacePath = Get-HelixActiveWorkspacePath -HelixRoot $TargetRoot
if (-not (Test-Path $activeWorkspacePath)) {
    Add-WarningLine "Missing active workspace pointer (.helix/active-workspace.yml)"
}

$repoIndex = @{}
if ($hasRegistry) {
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
