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

function Resolve-WorkspaceArtifactPath {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [string]$ArtifactValue
    )

    if ([string]::IsNullOrWhiteSpace($ArtifactValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($ArtifactValue)) {
        return [System.IO.Path]::GetFullPath($ArtifactValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $ArtifactValue))
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $normalizedPath = [System.IO.Path]::GetFullPath($Path)

    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedRoot + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-DirectoryHasFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Test-Path $Path) -and (@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-AgentBaseName {
    param([Parameter(Mandatory = $true)][string]$FileName)

    $name = [System.IO.Path]::GetFileName($FileName)
    if ($name -match '^(?<base>.+)\.agent\.md$') {
        return $Matches['base']
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($name)
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

$installedTemplatePath = Join-Path $TargetRoot 'helix/templates/agent.agent.md.template'
$legacyTemplatePath = Join-Path $TargetRoot 'templates/agent.agent.md.template'
$agentTemplatePath = if (Test-Path $installedTemplatePath) {
    $installedTemplatePath
} else {
    $legacyTemplatePath
}

if (Test-Path $agentTemplatePath) {
    $templateHead = Get-Content -LiteralPath $agentTemplatePath -TotalCount 12
    if ($templateHead -match '^model:\s*\[') {
        $templateLabel = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $agentTemplatePath
        Add-Issue "Template '$templateLabel' uses malformed custom agent frontmatter: 'model' must be a string, not an array."
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
$registryResolution = Resolve-HelixRegistryPath -HelixRoot $TargetRoot -AllowMissing
$registryPath = [string]$registryResolution.path
$registryManifestName = [string]$registryResolution.display_name
$hasInstallState = Test-Path $installStatePath
$hasRegistry = $registryResolution.source -ne 'missing'

if (-not $hasInstallState -and -not $hasRegistry) {
    Add-WarningLine "Helix instance state is not bootstrapped in '$TargetRoot'. Missing '.helix/install-state.yml' and canonical 'helix-repos.yml' (legacy fallback 'repos.yml' also not found). Run install-helix.ps1 in a target meta repo before using doctor for instance validation."
} else {
    if (-not $hasInstallState) {
        Add-Issue "Missing .helix/install-state.yml"
    }

    if (-not $hasRegistry) {
        Add-Issue "Missing helix-repos.yml (legacy fallback repos.yml not found)"
    } elseif ($registryResolution.source -eq 'legacy') {
        Add-WarningLine "Using legacy registry manifest 'repos.yml'. Rename it to canonical 'helix-repos.yml'."
    }
}

$activeWorkspacePath = Get-HelixActiveWorkspacePath -HelixRoot $TargetRoot
$activeWorkspaceId = $null
if (-not (Test-Path $activeWorkspacePath)) {
    Add-WarningLine "Missing active workspace pointer (.helix/active-workspace.yml)"
} else {
    try {
        $activeWorkspaceState = Import-HelixYamlFile -Path $activeWorkspacePath
        $activeWorkspaceId = [string]$activeWorkspaceState.active
        if ([string]::IsNullOrWhiteSpace($activeWorkspaceId)) {
            Add-WarningLine "Active workspace pointer '$([System.IO.Path]::GetFileName($activeWorkspacePath))' does not contain a valid 'active' workspace id."
            $activeWorkspaceId = $null
        }
    } catch {
        Add-WarningLine "Could not parse active workspace pointer '$([System.IO.Path]::GetFileName($activeWorkspacePath))'."
    }
}

$installedAssetRoot = Join-Path $TargetRoot 'helix'
if (Test-Path $installedAssetRoot) {
    $legacyDirectoryWarnings = [ordered]@{
        'decisions' = "Legacy root 'decisions/' contains content. Move it manually to 'workspaces/<workspace-id>/decisions/' if still relevant."
        'task-boards' = "Legacy root 'task-boards/' contains content. Move it manually to 'workspaces/<workspace-id>/task-boards/' if still relevant."
        'docs' = "Legacy root 'docs/' still contains files. Installed managed docs now live under 'helix/docs/'."
        'scripts' = "Legacy root 'scripts/' still contains files. Installed managed scripts now live under 'helix/scripts/'."
        'templates' = "Legacy root 'templates/' still contains files. Installed managed templates now live under 'helix/templates/'."
    }

    foreach ($legacyDirectory in $legacyDirectoryWarnings.Keys) {
        $legacyPath = Join-Path $TargetRoot $legacyDirectory
        if (Test-DirectoryHasFiles -Path $legacyPath) {
            Add-WarningLine $legacyDirectoryWarnings[$legacyDirectory]
        }
    }
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
            Add-Issue "Duplicate repo id '$repoId' in $registryManifestName"
        } else {
            $seenIds[$repoId] = $true
        }

        if ($seenPaths.ContainsKey($localPath)) {
            Add-Issue "Duplicate repo local_path '$localPath' in $registryManifestName"
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
                $artifactPath = Resolve-WorkspaceArtifactPath -WorkspaceRoot $_.FullName -ArtifactValue ([string]$workspace.artifacts[$artifactKey])
                if (-not (Test-Path $artifactPath)) {
                    Add-WarningLine "Workspace '$($_.Name)' artifact '$artifactKey' points to missing path '$artifactPath'."
                }
            }
        }

        $legacyArtifactRoots = [ordered]@{
            'task_board_dir' = 'task-boards'
            'decisions_dir' = 'decisions'
        }

        foreach ($artifactKey in $legacyArtifactRoots.Keys) {
            if (-not $workspace.artifacts.Contains($artifactKey) -or -not $workspace.artifacts[$artifactKey]) {
                continue
            }

            $artifactPath = Resolve-WorkspaceArtifactPath -WorkspaceRoot $_.FullName -ArtifactValue ([string]$workspace.artifacts[$artifactKey])
            if (-not (Test-PathWithinRoot -Path $artifactPath -Root $_.FullName)) {
                Add-WarningLine "Workspace '$($_.Name)' artifact '$artifactKey' resolves outside the workspace root: '$artifactPath'."
                continue
            }

            $legacyRootPath = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $legacyArtifactRoots[$artifactKey]))
            if ($artifactPath.Equals($legacyRootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-WarningLine "Workspace '$($_.Name)' artifact '$artifactKey' points to legacy root '$($legacyArtifactRoots[$artifactKey])/' instead of staying under 'workspaces/$($_.Name)/'."
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($activeWorkspaceId)) {
    $activeWorkspaceManifestPath = $null
    $activeWorkspace = $null
    $activeWorkspaceRoot = Join-Path $TargetRoot "workspaces/$activeWorkspaceId"

    try {
        $activeWorkspaceManifestPath = Get-HelixWorkspaceManifestPath -HelixRoot $TargetRoot -Workspace $activeWorkspaceId
        $activeWorkspace = Import-HelixYamlFile -Path $activeWorkspaceManifestPath
        $activeWorkspaceRoot = Split-Path -Parent $activeWorkspaceManifestPath
    } catch {
        Add-WarningLine "Could not resolve manifest for active workspace '$activeWorkspaceId'."
    }

    if ($null -ne $activeWorkspace -and $activeWorkspace.repos) {
        foreach ($workspaceRepo in $activeWorkspace.repos) {
            $repoId = [string]$workspaceRepo.repo_id
            if ([string]::IsNullOrWhiteSpace($repoId)) {
                continue
            }

            $expectedWorkspaceRepoPath = [System.IO.Path]::GetFullPath((Join-Path $activeWorkspaceRoot "repos/$repoId"))
            if (Test-Path $expectedWorkspaceRepoPath) {
                continue
            }

            $legacyCandidates = @()
            if ($repoIndex.ContainsKey($repoId)) {
                $localPath = [string]$repoIndex[$repoId].local_path
                if (-not [string]::IsNullOrWhiteSpace($localPath)) {
                    $legacyCandidates += [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $localPath))
                }
            }
            $legacyCandidates += [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $repoId))
            $legacyCandidates = @($legacyCandidates | Sort-Object -Unique)
            $legacyExisting = @($legacyCandidates | Where-Object { Test-Path $_ })

            if ($legacyExisting.Count -gt 0) {
                $legacyRelativePaths = @($legacyExisting | ForEach-Object {
                        Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $_
                    }) -join "', '"
                Add-WarningLine "Active workspace repo '$repoId' is not under 'workspaces/$activeWorkspaceId/repos/'. Found legacy path(s): '$legacyRelativePaths'. Re-run setup-workspace.ps1 or migrate manually."
                continue
            }

            $expectedRelativePath = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $expectedWorkspaceRepoPath
            Add-WarningLine "Active workspace repo '$repoId' is missing expected path '$expectedRelativePath'. Re-run setup-workspace.ps1."
        }
    }

    $rootCodeWorkspacePath = Join-Path $TargetRoot "$activeWorkspaceId.code-workspace"
    if (-not (Test-Path $rootCodeWorkspacePath)) {
        $workspaceCodeWorkspacePath = Join-Path $activeWorkspaceRoot "$activeWorkspaceId.code-workspace"
        if (Test-Path $workspaceCodeWorkspacePath) {
            Add-WarningLine "Workspace code-workspace exists only at 'workspaces/$activeWorkspaceId/$activeWorkspaceId.code-workspace'. Re-run setup-workspace.ps1 to generate '$activeWorkspaceId.code-workspace' at repo root."
        } else {
            Add-WarningLine "Missing root code-workspace '$activeWorkspaceId.code-workspace'. Re-run setup-workspace.ps1."
        }
    }

    $workspaceInstructionsPath = Join-Path $TargetRoot ".github/instructions/$activeWorkspaceId.workspace.instructions.md"
    if (-not (Test-Path $workspaceInstructionsPath)) {
        Add-WarningLine "Missing generated instruction summary '.github/instructions/$activeWorkspaceId.workspace.instructions.md'. Re-run setup-workspace.ps1."
    }
}

$userCopilotAgentsDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot/agents'
if ((Test-Path $agentDir) -and (Test-Path $userCopilotAgentsDir)) {
    $projectAgentFiles = @(Get-ChildItem -Path $agentDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)
    $userAgentFiles = @(Get-ChildItem -Path $userCopilotAgentsDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)

    if ($projectAgentFiles.Count -gt 0 -and $userAgentFiles.Count -gt 0) {
        $projectAgentsByBaseName = @{}
        foreach ($projectAgentFile in $projectAgentFiles) {
            $projectAgentBaseName = Get-AgentBaseName -FileName $projectAgentFile.Name
            if (-not $projectAgentsByBaseName.ContainsKey($projectAgentBaseName)) {
                $projectAgentsByBaseName[$projectAgentBaseName] = @()
            }
            $projectAgentsByBaseName[$projectAgentBaseName] += $projectAgentFile.Name
        }

        foreach ($userAgentFile in $userAgentFiles) {
            $userAgentBaseName = Get-AgentBaseName -FileName $userAgentFile.Name
            if ($projectAgentsByBaseName.ContainsKey($userAgentBaseName)) {
                Add-WarningLine "User-level agent collision for '$userAgentBaseName': '~/.copilot/agents/$($userAgentFile.Name)' overrides project '.github/agents/$($projectAgentsByBaseName[$userAgentBaseName][0])'."
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
