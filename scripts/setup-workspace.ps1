[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [string]$TargetRoot = (Get-Location).Path,
    [switch]$CloneMissing,
    [switch]$FetchExisting,
    [switch]$IncludeClaudeSettings,
    [switch]$SkipClaudeSettings
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$registryPath = Join-Path $TargetRoot 'repos.yml'
if (-not (Test-Path $registryPath)) {
    throw "No repos.yml found in '$TargetRoot'."
}

$workspacePath = Get-HelixWorkspaceManifestPath -HelixRoot $TargetRoot -Workspace $Workspace
$workspaceDir = Split-Path -Parent $workspacePath
$workspaceName = Split-Path $workspaceDir -Leaf

$registry = Import-HelixYamlFile -Path $registryPath
$workspaceManifest = Import-HelixYamlFile -Path $workspacePath

$repoIndex = @{}
foreach ($repo in $registry.repos) {
    $repoIndex[[string]$repo.id] = $repo
}

$folders = @(
    [ordered]@{
        name = Split-Path $TargetRoot -Leaf
        path = Get-HelixRelativePath -BasePath $workspaceDir -TargetPath $TargetRoot
    }
)

$repoStates = @()

foreach ($workspaceRepo in $workspaceManifest.repos) {
    $repoId = [string]$workspaceRepo.repo_id
    if (-not $repoIndex.ContainsKey($repoId)) {
        throw "Workspace '$workspaceName' references repo_id '$repoId' that is not present in repos.yml."
    }

    $repoDef = $repoIndex[$repoId]
    $repoPath = Join-Path $TargetRoot ([string]$repoDef.local_path)
    $repoDir = Split-Path -Parent $repoPath

    if (-not (Test-Path $repoPath) -and $CloneMissing) {
        New-HelixDirectory -Path $repoDir
        Write-Host "Cloning $repoId into $repoPath"
        & git clone ([string]$repoDef.remote) $repoPath
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed for '$repoId'."
        }

        $branch = if ($workspaceRepo.Contains('branch') -and $workspaceRepo.branch) { [string]$workspaceRepo.branch } elseif ($repoDef.Contains('default_branch') -and $repoDef.default_branch) { [string]$repoDef.default_branch } elseif ($registry.defaults.default_branch) { [string]$registry.defaults.default_branch } else { 'main' }
        if ($branch -and $branch -ne 'main') {
            & git -C $repoPath checkout $branch
        }
    } elseif ((Test-Path $repoPath) -and $FetchExisting) {
        Write-Host "Fetching $repoId"
        & git -C $repoPath fetch
    }

    $folders += [ordered]@{
        name = $repoId
        path = Get-HelixRelativePath -BasePath $workspaceDir -TargetPath $repoPath
    }

    $repoState = Get-HelixRepoReadiness -RepoId $repoId -RepoPath $repoPath
    $repoState.local_path = [string]$repoDef.local_path
    if ($repoDef.Contains('remote')) {
        $repoState.git.remote = [string]$repoDef.remote
    }
    $repoStates += $repoState

    $repoStatePath = Join-Path $TargetRoot ".helix/repo-state/$repoId.yml"
    Write-HelixYamlFile -Path $repoStatePath -Value $repoState
}

$workspaceConfig = [ordered]@{
    folders = $folders
    settings = [ordered]@{
        'chat.agentFilesLocations' = @(
            [ordered]@{ source = '.github/agents' }
        )
        'chat.skillsLocations' = @(
            [ordered]@{ source = '.github/skills' }
        )
        'chat.hookFilesLocations' = @(
            [ordered]@{ source = '.github/hooks' }
        )
    }
}

$workspaceFile = Join-Path $workspaceDir "$workspaceName.code-workspace"
$workspaceConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $workspaceFile

$activeWorkspace = [ordered]@{
    schema_version = 1
    active = $workspaceName
    updated_at = (Get-Date).ToUniversalTime().ToString('o')
}
Write-HelixYamlFile -Path (Join-Path $TargetRoot '.helix/active-workspace.yml') -Value $activeWorkspace

if ($SkipClaudeSettings) {
    Write-Warning "SkipClaudeSettings is deprecated because Claude settings are no longer written by default. Use -IncludeClaudeSettings when you explicitly want Claude Desktop configuration."
}

if ($IncludeClaudeSettings) {
    $claudeDir = Join-Path $TargetRoot '.claude'
    New-HelixDirectory -Path $claudeDir
    $settingsPath = Join-Path $claudeDir 'settings.local.json'
    $additionalDirs = @()
    foreach ($workspaceRepo in $workspaceManifest.repos) {
        $repoDef = $repoIndex[[string]$workspaceRepo.repo_id]
        $additionalDirs += [string]$repoDef.local_path
    }

    $settings = [ordered]@{
        permissions = [ordered]@{
            additionalDirectories = $additionalDirs
        }
    }
    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath
}

$statusTable = $repoStates | ForEach-Object {
    [pscustomobject]@{
        Repo = $_.repo_id
        Present = $_.present
        Ready = $_.readiness.state
        Recommended = $_.readiness.recommended_next_step
        Branch = $_.git.branch
    }
}

Write-Host "Workspace '$workspaceName' is active."
$statusTable | Format-Table -AutoSize
Write-Host "Generated workspace file: $workspaceFile"
