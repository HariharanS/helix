[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [switch]$WriteRepoState
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

$invocationCwd = (Get-Location).Path
$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$issues = @()
$warnings = @()

$normalizedCwd = [System.IO.Path]::GetFullPath($invocationCwd).TrimEnd('\', '/')
$normalizedRoot = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\', '/')
if (-not [string]::Equals($normalizedCwd, $normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    $script:warnings += "doctor.ps1 invoked from a non-meta-root CWD ('$invocationCwd'). Helix sessions should run with the meta-root ('$TargetRoot') as CWD so hosts discover .github/skills, .github/prompts, and AGENTS.md correctly."
}

function Add-Issue([string]$Message) {
    $script:issues += $Message
}

function Add-WarningLine([string]$Message) {
    $script:warnings += $Message
}

if ($WriteRepoState) {
    Add-WarningLine "-WriteRepoState is deprecated and no longer writes repo-state. Run setup-workspace.ps1 so repo-state uses the active workspace checkout paths."
}

function Test-CodeReviewGraphPythonModule {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    try {
        & $Command @Arguments 1>$null 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-CodeReviewGraphRuntimeAvailable {
    if (Get-Command uvx -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Command code-review-graph -ErrorAction SilentlyContinue) {
        return $true
    }

    if ((Get-Command python -ErrorAction SilentlyContinue) -and
        (Test-CodeReviewGraphPythonModule -Command 'python' -Arguments @('-c', 'import code_review_graph'))) {
        return $true
    }

    if ((Get-Command py -ErrorAction SilentlyContinue) -and
        (Test-CodeReviewGraphPythonModule -Command 'py' -Arguments @('-3', '-c', 'import code_review_graph'))) {
        return $true
    }

    return $false
}

function Test-CodeReviewGraphServerConfig {
    param(
        [Parameter(Mandatory = $true)][string]$LocationLabel,
        [string]$Command
    )

    if (-not [string]::IsNullOrWhiteSpace($Command) -and [System.IO.Path]::IsPathRooted($Command)) {
        Add-WarningLine "$LocationLabel pins 'code-review-graph' to the absolute path '$Command'. This is instance-specific and can break on clean installs. Re-run 'helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode mcp -Bootstrap' to normalize it."
    }

    $runtimeAvailable = Test-CodeReviewGraphRuntimeAvailable
    if (-not $runtimeAvailable) {
        Add-WarningLine "$LocationLabel enables 'code-review-graph', but no verified runtime was found (uvx, code-review-graph, python -m code_review_graph, or py -3 -m code_review_graph). In mcp mode this is a setup issue; re-run set-context-provider.ps1 -Mode mcp -Bootstrap."
    }
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

$legacyProjectMcpPath = Join-Path $TargetRoot '.mcp.json'
$legacyProjectContainsServer = $false
$vscodeContainsServer = $false
$cliContainsServer = $false
if (Test-Path $legacyProjectMcpPath) {
    try {
        $mcpConfig = Get-Content -LiteralPath $legacyProjectMcpPath -Raw | ConvertFrom-Json
        $hasCodeReviewGraph = $null -ne $mcpConfig.mcpServers -and ($mcpConfig.mcpServers.PSObject.Properties.Name -contains 'code-review-graph')
        $legacyProjectContainsServer = $hasCodeReviewGraph
        if ($hasCodeReviewGraph) {
            $server = $mcpConfig.mcpServers.'code-review-graph'
            $command = if ($null -ne $server) { [string]$server.command } else { '' }
            Add-WarningLine "Legacy root '.mcp.json' contains 'code-review-graph'. Helix now prefers '.vscode/mcp.json' for VS Code and '~/.copilot/mcp-config.json' for Copilot CLI."
            Test-CodeReviewGraphServerConfig -LocationLabel "Legacy root '.mcp.json'" -Command $command
        }
    } catch {
        Add-Issue "Invalid JSON in '.mcp.json'."
    }
}

$vscodeMcpPath = Join-Path $TargetRoot '.vscode/mcp.json'
if (Test-Path $vscodeMcpPath) {
    try {
        $vscodeConfig = Get-Content -LiteralPath $vscodeMcpPath -Raw | ConvertFrom-Json
        $hasCodeReviewGraph = $null -ne $vscodeConfig.servers -and ($vscodeConfig.servers.PSObject.Properties.Name -contains 'code-review-graph')
        $vscodeContainsServer = $hasCodeReviewGraph
        if ($hasCodeReviewGraph) {
            $server = $vscodeConfig.servers.'code-review-graph'
            $command = if ($null -ne $server) { [string]$server.command } else { '' }
            Test-CodeReviewGraphServerConfig -LocationLabel "'.vscode/mcp.json'" -Command $command
        }
    } catch {
        Add-Issue "Invalid JSON in '.vscode/mcp.json'."
    }
}

$userCliMcpPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot/mcp-config.json'
if (Test-Path $userCliMcpPath) {
    try {
        $userCliMcpConfig = Get-Content -LiteralPath $userCliMcpPath -Raw | ConvertFrom-Json
        $hasCodeReviewGraph = $null -ne $userCliMcpConfig.mcpServers -and ($userCliMcpConfig.mcpServers.PSObject.Properties.Name -contains 'code-review-graph')
        $cliContainsServer = $hasCodeReviewGraph
        if ($hasCodeReviewGraph) {
            $server = $userCliMcpConfig.mcpServers.'code-review-graph'
            $command = if ($null -ne $server) { [string]$server.command } else { '' }
            Test-CodeReviewGraphServerConfig -LocationLabel "'~/.copilot/mcp-config.json'" -Command $command
        }
    } catch {
        Add-Issue "Invalid JSON in '~/.copilot/mcp-config.json'."
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

    $skillIndexPath = Join-Path $TargetRoot '.helix/skills/index.yml'
    if (-not (Test-Path $skillIndexPath)) {
        Add-WarningLine "Missing skill projection ledger '.helix/skills/index.yml'. Re-run install-helix.ps1 or setup-workspace.ps1 so the active workspace's skills are projected into the meta root."
    }
}

$contextProvidersPath = Join-Path $TargetRoot '.helix/context-providers.yml'
$crgMode = $null
if (($hasInstallState -or $hasRegistry) -and -not (Test-Path $contextProvidersPath)) {
    Add-Issue "Missing .helix/context-providers.yml"
} elseif (Test-Path $contextProvidersPath) {
    try {
        $contextProviders = Import-HelixYamlFile -Path $contextProvidersPath
        if ($contextProviders.providers -and
            $contextProviders.providers.code_review_graph -and
            $contextProviders.providers.code_review_graph.mode) {
            $crgMode = [string]$contextProviders.providers.code_review_graph.mode
        }
    } catch {
        Add-Issue "Could not parse .helix/context-providers.yml"
    }
}

if ($hasInstallState -or $hasRegistry) {
    if ([string]::IsNullOrWhiteSpace($crgMode)) {
        Add-Issue ".helix/context-providers.yml does not define providers.code_review_graph.mode"
    } elseif ($crgMode -eq 'mcp') {
        if (-not $vscodeContainsServer) {
            Add-Issue "CRG mode is 'mcp' but '.vscode/mcp.json' does not configure code-review-graph."
        }

        if (-not $cliContainsServer) {
            Add-Issue "CRG mode is 'mcp' but '~/.copilot/mcp-config.json' does not configure code-review-graph."
        }

        if (-not (Test-CodeReviewGraphRuntimeAvailable)) {
            Add-Issue "CRG mode is 'mcp' but no verified runtime was found. Run 'helix/scripts/set-context-provider.ps1 -Provider code-review-graph -Mode mcp -Bootstrap'."
        }
    } elseif ($crgMode -eq 'off') {
        Add-WarningLine "CRG mode is 'off'. This is an emergency fallback; normal Helix setup expects code-review-graph MCP to be configured."
    } else {
        Add-Issue "Unsupported code_review_graph.mode '$crgMode' in .helix/context-providers.yml."
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

    $verificationPolicyDeclared = $false
    if ($null -ne $activeWorkspace.artifacts -and $activeWorkspace.artifacts.Contains('verification_policy') -and $activeWorkspace.artifacts['verification_policy']) {
        $verificationPolicyDeclared = $true
    }

    $verificationPolicyPath = if ($verificationPolicyDeclared) {
        Resolve-WorkspaceArtifactPath -WorkspaceRoot $activeWorkspaceRoot -ArtifactValue ([string]$activeWorkspace.artifacts['verification_policy'])
    } else {
        Join-Path $activeWorkspaceRoot 'verification-policy.yml'
    }

    $verificationBetaEnabled = $verificationPolicyDeclared
    if ($verificationPolicyDeclared -and -not (Test-Path $verificationPolicyPath)) {
        Add-WarningLine "Active workspace '$activeWorkspaceId' declares 'verification_policy' but the file is missing at '$verificationPolicyPath'. Re-run setup-workspace.ps1 to seed policy scaffolding or fix the artifact path."
    }

    if ($verificationBetaEnabled -and $null -ne $activeWorkspace -and $activeWorkspace.repos) {
        $capabilityRoot = Join-Path $TargetRoot '.helix/repo-capabilities'
        foreach ($workspaceRepo in $activeWorkspace.repos) {
            $repoId = [string]$workspaceRepo.repo_id
            if ([string]::IsNullOrWhiteSpace($repoId)) {
                continue
            }

            $repoCapabilityPath = Join-Path $capabilityRoot "$repoId.yml"
            if (-not (Test-Path $repoCapabilityPath)) {
                Add-WarningLine "Active workspace repo '$repoId' is missing '.helix/repo-capabilities/$repoId.yml'. Re-run setup-workspace.ps1 to refresh capability discovery."
            }
        }
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

$skillIndexPath = Join-Path $TargetRoot '.helix/skills/index.yml'
if (Test-Path $skillIndexPath) {
    try {
        $skillIndex = Read-HelixSkillIndex -Path $skillIndexPath
    } catch {
        Add-WarningLine "Could not parse '.helix/skills/index.yml': $($_.Exception.Message)"
        $skillIndex = $null
    }

    if ($null -ne $skillIndex -and $skillIndex.Contains('skills')) {
        foreach ($skillEntry in @($skillIndex['skills'])) {
            if (-not ($skillEntry -is [System.Collections.IDictionary])) { continue }
            if (-not $skillEntry.Contains('projection')) { continue }
            $proj = $skillEntry['projection']
            if (-not ($proj -is [System.Collections.IDictionary])) { continue }
            if (-not $proj.Contains('checksum')) { continue }

            $storedChecksum = [string]$proj['checksum']
            if ([string]::IsNullOrWhiteSpace($storedChecksum)) { continue }

            $skillName = if ($skillEntry.Contains('name')) { [string]$skillEntry['name'] } else { '<unknown>' }
            $skillPathRel = if ($skillEntry.Contains('path')) { [string]$skillEntry['path'] } else { $null }
            $projectedFolder = $null
            if (-not [string]::IsNullOrWhiteSpace($skillPathRel)) {
                $resolvedPath = Join-Path $TargetRoot $skillPathRel
                if (Test-Path $resolvedPath -PathType Leaf) {
                    $projectedFolder = Split-Path -Parent $resolvedPath
                } elseif (Test-Path $resolvedPath -PathType Container) {
                    $projectedFolder = $resolvedPath
                }
            }

            $fromRepo = if ($proj.Contains('from_repo')) { [string]$proj['from_repo'] } else { '<unknown>' }
            $fromPath = if ($proj.Contains('from_path')) { [string]$proj['from_path'] } else { '<unknown>' }

            if ($null -ne $projectedFolder -and (Test-Path $projectedFolder)) {
                $currentProjectedChecksum = Get-HelixSkillContentChecksum -SkillFolder $projectedFolder
                if ($null -ne $currentProjectedChecksum -and -not [string]::Equals($currentProjectedChecksum, $storedChecksum, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-WarningLine "Projected skill '$skillName' has been hand-edited; edits should happen in source repo '$fromRepo' at path '$fromPath', then re-run helix/scripts/setup-workspace.ps1."
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($activeWorkspaceId) -and -not [string]::IsNullOrWhiteSpace($fromRepo) -and $fromRepo -ne '<unknown>' -and -not [string]::IsNullOrWhiteSpace($fromPath) -and $fromPath -ne '<unknown>') {
                $sourceFolder = Join-Path $TargetRoot "workspaces/$activeWorkspaceId/repos/$fromRepo/$fromPath"
                if (Test-Path $sourceFolder) {
                    $currentSourceChecksum = Get-HelixSkillContentChecksum -SkillFolder $sourceFolder
                    if ($null -ne $currentSourceChecksum -and -not [string]::Equals($currentSourceChecksum, $storedChecksum, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Add-WarningLine "Projected skill '$skillName' is stale: source repo '$fromRepo' at '$fromPath' has changed since projection. Re-run helix/scripts/setup-workspace.ps1 to refresh."
                    }
                }
            }
        }
    }
}

$instructionMarker = '<!-- Generated by helix/scripts/setup-workspace.ps1 -->'

$copilotInstructionsPath = Join-Path $TargetRoot '.github/copilot-instructions.md'
if (Test-Path $copilotInstructionsPath -PathType Leaf) {
    Add-WarningLine "Found user-authored '.github/copilot-instructions.md'. Helix manages instructions through AGENTS.md; this file is not generated or maintained by Helix. See helix/docs/agents-md-authoring.md."
}

$instructionsDir = Join-Path $TargetRoot '.github/instructions'
if (Test-Path $instructionsDir -PathType Container) {
    $instructionFiles = @(Get-ChildItem -LiteralPath $instructionsDir -File -Recurse -Filter '*.instructions.md' -ErrorAction SilentlyContinue)
    foreach ($instructionFile in $instructionFiles) {
        $isHelixGenerated = $false
        try {
            $content = [System.IO.File]::ReadAllText($instructionFile.FullName)
            if ($content.Contains($instructionMarker)) { $isHelixGenerated = $true }
        } catch {
            # If unreadable, treat as user-authored to err on the side of warning.
        }
        if (-not $isHelixGenerated) {
            $instructionRel = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $instructionFile.FullName
            Add-WarningLine "Found user-authored '$instructionRel'. Helix manages instructions through AGENTS.md; this file is not generated or maintained by Helix. See helix/docs/agents-md-authoring.md."
        }
    }
}

$claudeMdPath = Join-Path $TargetRoot 'CLAUDE.md'
if (Test-Path $claudeMdPath -PathType Leaf) {
    Add-WarningLine "Found user-authored 'CLAUDE.md' at the meta-root. Helix manages instructions through AGENTS.md; this file is not generated or maintained by Helix. See helix/docs/agents-md-authoring.md."
}

$geminiMdPath = Join-Path $TargetRoot 'GEMINI.md'
if (Test-Path $geminiMdPath -PathType Leaf) {
    Add-WarningLine "Found user-authored 'GEMINI.md' at the meta-root. Helix manages instructions through AGENTS.md; this file is not generated or maintained by Helix. See helix/docs/agents-md-authoring.md."
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
