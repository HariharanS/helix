[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Workspace,
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

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

function Test-HelixPlaceholderValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    return $Value -match 'your-org' -or $Value -in @(
        'example-feature',
        'service-a',
        'web-app',
        'Example Feature',
        'Short description of the feature-space',
        'One-sentence desired outcome'
    )
}

function Assert-RegistryAndWorkspaceReady {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$RegistryManifestName,
        [Parameter(Mandatory = $true)]$WorkspaceManifest,
        [Parameter(Mandatory = $true)][string]$WorkspaceName
    )

    if (-not $Registry.repos -or @($Registry.repos).Count -eq 0) {
        throw "$RegistryManifestName does not define any repos. Update the registry before running setup-workspace.ps1."
    }

    $seenIds = @{}
    $seenPaths = @{}

    foreach ($repo in $Registry.repos) {
        $repoId = [string]$repo.id
        $remote = [string]$repo.remote
        $localPath = [string]$repo.local_path

        if ([string]::IsNullOrWhiteSpace($repoId)) {
            throw "$RegistryManifestName contains a repo entry without an id."
        }

        if ([string]::IsNullOrWhiteSpace($remote)) {
            throw "Repo '$repoId' is missing a remote in $RegistryManifestName."
        }

        if ([string]::IsNullOrWhiteSpace($localPath)) {
            throw "Repo '$repoId' is missing a local_path in $RegistryManifestName."
        }

        if ($seenIds.ContainsKey($repoId)) {
            throw "Duplicate repo id '$repoId' in $RegistryManifestName."
        }
        $seenIds[$repoId] = $true

        if ($seenPaths.ContainsKey($localPath)) {
            throw "Duplicate repo local_path '$localPath' in $RegistryManifestName."
        }
        $seenPaths[$localPath] = $true

        if (Test-HelixPlaceholderValue -Value $remote) {
            throw "Repo '$repoId' in $RegistryManifestName still uses a template placeholder remote ('$remote'). Update helix-repos.yml before running setup-workspace.ps1."
        }
    }

    if (-not $WorkspaceManifest.repos -or @($WorkspaceManifest.repos).Count -eq 0) {
        throw "Workspace '$WorkspaceName' does not define any repos. Update the workspace manifest before running setup-workspace.ps1."
    }

    foreach ($workspaceRepo in $WorkspaceManifest.repos) {
        $repoId = [string]$workspaceRepo.repo_id
        if ([string]::IsNullOrWhiteSpace($repoId)) {
            throw "Workspace '$WorkspaceName' contains a repo entry without repo_id."
        }
    }
}

function Get-WorkspaceRepoRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceName,
        [Parameter(Mandatory = $true)][string]$RepoId
    )

    return "workspaces/$WorkspaceName/repos/$RepoId"
}

function Resolve-HelixTemplatePath {
    param(
        [Parameter(Mandatory = $true)][string]$HelixRoot,
        [Parameter(Mandatory = $true)][string]$TemplateFileName
    )

    $candidates = @(
        (Join-Path $HelixRoot "helix/templates/$TemplateFileName"),
        (Join-Path $HelixRoot "templates/$TemplateFileName")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Could not resolve template '$TemplateFileName'. Checked: $($candidates -join ', ')"
}

function ConvertFrom-HelixRepoIdCsv {
    param([string]$Csv)

    $repoIds = @()
    $seen = @{}

    foreach ($rawRepoId in ($Csv -split ',')) {
        $repoId = $rawRepoId.Trim()
        if ([string]::IsNullOrWhiteSpace($repoId)) {
            continue
        }

        if ($seen.ContainsKey($repoId)) {
            throw "Duplicate repo id '$repoId' in -ReposCsv."
        }

        $seen[$repoId] = $true
        $repoIds += $repoId
    }

    if ($repoIds.Count -eq 0) {
        throw "-ReposCsv was provided but did not contain any repo ids."
    }

    return ,$repoIds
}

function New-HelixWorkspaceManifestFromReposCsv {
    param(
        [Parameter(Mandatory = $true)][string]$HelixRoot,
        [Parameter(Mandatory = $true)][string]$WorkspaceName,
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$RegistryManifestName,
        [Parameter(Mandatory = $true)][string]$Csv,
        [string]$DisplayName,
        [string]$Description,
        [string]$Objective
    )

    if ($WorkspaceName -match '[\\/]') {
        throw "-ReposCsv workspace seeding requires a workspace id such as 'directeddebit', not a path."
    }

    if (-not $Registry.repos -or @($Registry.repos).Count -eq 0) {
        throw "$RegistryManifestName does not define any repos. Update the registry before creating a workspace manifest from -ReposCsv."
    }

    $repoIndex = @{}
    foreach ($repo in $Registry.repos) {
        $repoId = [string]$repo.id
        if (-not [string]::IsNullOrWhiteSpace($repoId)) {
            $repoIndex[$repoId] = $repo
        }
    }

    $workspaceRepoEntries = @()
    foreach ($repoId in (ConvertFrom-HelixRepoIdCsv -Csv $Csv)) {
        if (-not $repoIndex.ContainsKey($repoId)) {
            throw "Cannot seed workspace '$WorkspaceName': repo_id '$repoId' is not present in $RegistryManifestName."
        }

        $repoDef = $repoIndex[$repoId]
        $role = if ($repoDef.Contains('default_role') -and $repoDef.default_role) {
            [string]$repoDef.default_role
        } else {
            'supporting'
        }

        $branch = if ($repoDef.Contains('default_branch') -and $repoDef.default_branch) {
            [string]$repoDef.default_branch
        } elseif ($Registry.defaults -and $Registry.defaults.default_branch) {
            [string]$Registry.defaults.default_branch
        } else {
            'main'
        }

        $workspaceRepoEntries += [ordered]@{
            repo_id = $repoId
            role = $role
            branch = $branch
        }
    }

    $workspaceDir = Join-Path $HelixRoot "workspaces/$WorkspaceName"
    $workspacePath = Join-Path $workspaceDir 'workspace.yml'

    if (Test-Path $workspacePath) {
        throw "Workspace manifest already exists at '$workspacePath'. Edit it directly; -ReposCsv will not overwrite it."
    }

    $workspaceManifest = [ordered]@{
        schema_version = 1
        id = $WorkspaceName
        display_name = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $WorkspaceName } else { $DisplayName }
        description = if ([string]::IsNullOrWhiteSpace($Description)) { "Workspace generated from -ReposCsv." } else { $Description }
        status = 'draft'
        mode = 'interactive'
        workflow = 'full-rpi'
        objective = if ([string]::IsNullOrWhiteSpace($Objective)) { "Coordinate selected repos for $WorkspaceName." } else { $Objective }
        created_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        phase = [ordered]@{
            current = 'setup'
            last_completed = $null
        }
        ui_verification = $false
        repos = $workspaceRepoEntries
        artifacts = [ordered]@{
            refined_intent = 'refined-intent.md'
            prd = 'prd/index.md'
            tech_design = 'tech-design/index.md'
            task_board_dir = 'task-boards/'
            execution_plan_dir = 'execution-plans/'
            decisions_dir = 'decisions/'
        }
    }

    Write-HelixYamlFile -Path $workspacePath -Value $workspaceManifest
    Write-Host "Seeded workspace manifest: $workspacePath"

    return $workspacePath
}

function Remove-HelixGeneratedInstructionSummaries {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $instructionsRoot = Join-Path $TargetRoot '.github/instructions'
    if (-not (Test-Path $instructionsRoot)) {
        return 0
    }

    $marker = '<!-- Generated by helix/scripts/setup-workspace.ps1 -->'
    $removed = 0
    $instructionFiles = Get-ChildItem -LiteralPath $instructionsRoot -File -Filter '*.instructions.md' -ErrorAction SilentlyContinue
    foreach ($instructionFile in $instructionFiles) {
        try {
            $content = [System.IO.File]::ReadAllText($instructionFile.FullName)
            if ($content.Contains($marker)) {
                Remove-Item -LiteralPath $instructionFile.FullName -Force
                $removed += 1
            }
        } catch {
            Write-Warning "Could not inspect generated instruction summary '$($instructionFile.FullName)': $($_.Exception.Message)"
        }
    }

    $remaining = @(Get-ChildItem -LiteralPath $instructionsRoot -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $instructionsRoot -Force
    }

    return $removed
}

function Test-HelixCrgImport {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    try {
        $allArgs = @($Arguments) + @('-c', 'import code_review_graph')
        & $Command @allArgs *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-HelixCrgRunner {
    if (Get-Command uvx -ErrorAction SilentlyContinue) {
        return [ordered]@{ command = 'uvx'; args = @('code-review-graph') }
    }

    if (Get-Command code-review-graph -ErrorAction SilentlyContinue) {
        return [ordered]@{ command = 'code-review-graph'; args = @() }
    }

    if ((Get-Command python -ErrorAction SilentlyContinue) -and (Test-HelixCrgImport -Command 'python')) {
        return [ordered]@{ command = 'python'; args = @('-m', 'code_review_graph') }
    }

    if ((Get-Command py -ErrorAction SilentlyContinue) -and (Test-HelixCrgImport -Command 'py' -Arguments @('-3'))) {
        return [ordered]@{ command = 'py'; args = @('-3', '-m', 'code_review_graph') }
    }

    if ((Get-Command python3 -ErrorAction SilentlyContinue) -and (Test-HelixCrgImport -Command 'python3')) {
        return [ordered]@{ command = 'python3'; args = @('-m', 'code_review_graph') }
    }

    return $null
}

function Invoke-HelixCrgBuild {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Runner
    )

    $cmd = [string]$Runner['command']
    $prefix = @($Runner['args'])

    Write-Host "  CRG: build --repo $RepoPath"
    & $cmd @prefix 'build' '--repo' $RepoPath 2>&1 | Write-Host
    $buildExit = $LASTEXITCODE

    if ($buildExit -ne 0) {
        return [ordered]@{ status = 'failed'; stage = 'build'; exit_code = $buildExit }
    }

    & $cmd @prefix 'register' $RepoPath 2>&1 | Write-Host
    $registerExit = $LASTEXITCODE
    if ($registerExit -ne 0) {
        return [ordered]@{ status = 'failed'; stage = 'register'; exit_code = $registerExit }
    }

    & $cmd @prefix 'wiki' '--repo' $RepoPath 2>&1 | Write-Host
    $wikiExit = $LASTEXITCODE
    if ($wikiExit -ne 0) {
        return [ordered]@{ status = 'failed'; stage = 'wiki'; exit_code = $wikiExit }
    }

    $statusOutput = & $cmd @prefix 'status' '--repo' $RepoPath 2>&1
    $statusExit = $LASTEXITCODE
    $statusText = ($statusOutput | Out-String)
    $nodes = $null
    if ($statusText -match '(?i)(?:node_count|nodes?)["''\s:=]+(?<nodes>\d+)') {
        $nodes = [int]$Matches['nodes']
    }

    if ($statusExit -ne 0) {
        return [ordered]@{ status = 'failed'; stage = 'status'; exit_code = $statusExit }
    }

    if ($null -ne $nodes -and $nodes -le 0) {
        return [ordered]@{ status = 'failed'; stage = 'status'; exit_code = 0; reason = '0 nodes' }
    }

    return [ordered]@{
        status = 'built'
        stage = 'status'
        nodes = $nodes
    }
}

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$registryResolution = Resolve-HelixRegistryPath -HelixRoot $TargetRoot
$registryPath = [string]$registryResolution.path
$registryManifestName = [string]$registryResolution.display_name
if ($registryResolution.source -eq 'legacy') {
    Write-Warning "Using legacy registry manifest 'repos.yml'. Rename it to 'helix-repos.yml' when practical."
}

$registry = Import-HelixYamlFile -Path $registryPath

$seededWorkspaceManifest = $false
try {
    $workspacePath = Get-HelixWorkspaceManifestPath -HelixRoot $TargetRoot -Workspace $Workspace
} catch {
    if ([string]::IsNullOrWhiteSpace($ReposCsv)) {
        throw
    }

    $workspacePath = New-HelixWorkspaceManifestFromReposCsv `
        -HelixRoot $TargetRoot `
        -WorkspaceName $Workspace `
        -Registry $registry `
        -RegistryManifestName $registryManifestName `
        -Csv $ReposCsv `
        -DisplayName $DisplayName `
        -Description $Description `
        -Objective $Objective
    $seededWorkspaceManifest = $true
}

if (-not $seededWorkspaceManifest -and -not [string]::IsNullOrWhiteSpace($ReposCsv)) {
    Write-Warning "Workspace manifest already exists at '$workspacePath'. -ReposCsv was not applied."
}

$workspaceDir = Split-Path -Parent $workspacePath
$workspaceName = Split-Path $workspaceDir -Leaf

$workspaceManifest = Import-HelixYamlFile -Path $workspacePath

Assert-RegistryAndWorkspaceReady -Registry $registry -RegistryManifestName $registryManifestName -WorkspaceManifest $workspaceManifest -WorkspaceName $workspaceName

$repoIndex = @{}
foreach ($repo in $registry.repos) {
    $repoIndex[[string]$repo.id] = $repo
}

$workspaceFileBaseDir = $TargetRoot
$folders = @(
    [ordered]@{
        name = Split-Path $TargetRoot -Leaf
        path = Get-HelixRelativePath -BasePath $workspaceFileBaseDir -TargetPath $TargetRoot
    }
)

$repoStates = @()
$workspaceRepos = @()
$crgResults = @()

$crgModePath = Join-Path $TargetRoot '.helix/context-providers.yml'
$crgMode = 'mcp'
if (Test-Path $crgModePath) {
    try {
        $crgConfig = Import-HelixYamlFile -Path $crgModePath
        if ($crgConfig.providers -and $crgConfig.providers.code_review_graph -and $crgConfig.providers.code_review_graph.mode) {
            $crgMode = [string]$crgConfig.providers.code_review_graph.mode
        }
    } catch {
        throw "Could not parse '$crgModePath': $($_.Exception.Message). Fix context-providers.yml or set CRG mode to 'off' only as an emergency fallback."
    }
}

if ($crgMode -notin @('mcp', 'off')) {
    throw "Unsupported code_review_graph.mode '$crgMode' in '$crgModePath'. Use 'mcp' for normal setup or 'off' only as an emergency fallback."
}

$crgRunner = $null
if (-not $SkipGraphBuild -and $crgMode -eq 'mcp') {
    $crgRunner = Get-HelixCrgRunner
    if ($null -eq $crgRunner) {
        throw "CRG mode is 'mcp' but no verified CRG runner was found. Run './helix/scripts/set-context-provider.ps1 -Mode mcp -Bootstrap' or set CRG mode to 'off' only as an emergency fallback."
    }
} elseif ($SkipGraphBuild -and $crgMode -eq 'mcp') {
    throw "Cannot skip CRG graph build while mode is 'mcp'. Set CRG mode to 'off' only as an emergency fallback if you need default agent/search behavior."
}

foreach ($workspaceRepo in $workspaceManifest.repos) {
    $repoId = [string]$workspaceRepo.repo_id
    if (-not $repoIndex.ContainsKey($repoId)) {
        throw "Workspace '$workspaceName' references repo_id '$repoId' that is not present in $registryManifestName."
    }

    $repoDef = $repoIndex[$repoId]
    $repoRelativePath = Get-WorkspaceRepoRelativePath -WorkspaceName $workspaceName -RepoId $repoId
    $repoPath = Join-Path $TargetRoot $repoRelativePath
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
        path = Get-HelixRelativePath -BasePath $workspaceFileBaseDir -TargetPath $repoPath
    }

    $repoState = Get-HelixRepoReadiness -RepoId $repoId -RepoPath $repoPath
    $repoState.local_path = $repoRelativePath
    if ($repoDef.Contains('remote')) {
        $repoState.git.remote = [string]$repoDef.remote
    }
    $repoStates += $repoState

    $capabilityState = Get-HelixRepoCapabilities -RepoId $repoId -RepoPath $repoPath
    $capabilityState.local_path = $repoRelativePath

    $workspaceRepos += [ordered]@{
        repo_id = $repoId
        repo_path = $repoPath
        repo_relative_path = $repoRelativePath
    }

    $repoStatePath = Join-Path $TargetRoot ".helix/repo-state/$repoId.yml"
    Write-HelixYamlFile -Path $repoStatePath -Value $repoState

    $repoCapabilityPath = Join-Path $TargetRoot ".helix/repo-capabilities/$repoId.yml"
    Write-HelixYamlFile -Path $repoCapabilityPath -Value $capabilityState

    if ($repoState.present -and -not $SkipGraphBuild -and $crgMode -eq 'mcp' -and $null -ne $crgRunner) {
        try {
            $buildResult = Invoke-HelixCrgBuild -RepoPath $repoPath -Runner $crgRunner
        } catch {
            $buildResult = [ordered]@{ status = 'failed'; stage = 'build'; exit_code = -1; reason = $_.Exception.Message }
        }
        $crgResults += [pscustomobject]@{
            Repo = $repoId
            Status = $buildResult.status
            Stage = $buildResult.stage
            Detail = if ($buildResult.Contains('nodes') -and $null -ne $buildResult.nodes) { "nodes:$($buildResult.nodes)" } elseif ($buildResult.Contains('reason')) { $buildResult.reason } elseif ($buildResult.Contains('exit_code')) { "exit:$($buildResult.exit_code)" } else { '' }
        }

        if ($buildResult.status -ne 'built') {
            throw "CRG graph build failed for '$repoId' at stage '$($buildResult.stage)'. Set CRG mode to 'off' only as an emergency fallback if you need plain agent/search behavior."
        }
    }
}

$verificationPolicyDeclared = $false
$verificationPolicyPath = $null
if ($null -ne $workspaceManifest.artifacts -and $workspaceManifest.artifacts.Contains('verification_policy')) {
    $verificationPolicyArtifact = [string]$workspaceManifest.artifacts['verification_policy']
    if (-not [string]::IsNullOrWhiteSpace($verificationPolicyArtifact)) {
        $verificationPolicyDeclared = $true
        $verificationPolicyPath = if ([System.IO.Path]::IsPathRooted($verificationPolicyArtifact)) {
            [System.IO.Path]::GetFullPath($verificationPolicyArtifact)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $workspaceDir $verificationPolicyArtifact))
        }
    }
}

if ($verificationPolicyDeclared -and -not (Test-Path $verificationPolicyPath)) {
    $verificationPolicyTemplatePath = Resolve-HelixTemplatePath -HelixRoot $TargetRoot -TemplateFileName 'verification-policy.yml.template'
    $verificationPolicyDir = Split-Path -Parent $verificationPolicyPath
    if ($verificationPolicyDir) {
        New-HelixDirectory -Path $verificationPolicyDir
    }

    Copy-Item -LiteralPath $verificationPolicyTemplatePath -Destination $verificationPolicyPath -Force
    try {
        $verificationPolicy = Import-HelixYamlFile -Path $verificationPolicyPath
        $verificationPolicy.workspace_id = $workspaceName
        $verificationPolicy.last_seeded_at = (Get-Date).ToUniversalTime().ToString('o')
        Write-HelixYamlFile -Path $verificationPolicyPath -Value $verificationPolicy
    } catch {
        Write-Warning "Seeded verification policy at '$verificationPolicyPath' from template, but could not apply workspace metadata."
    }
}

$mentalModelPath = Join-Path $workspaceDir 'mental-model.md'
if (-not (Test-Path $mentalModelPath)) {
    $mentalModelTemplatePath = Resolve-HelixTemplatePath -HelixRoot $TargetRoot -TemplateFileName 'mental-model.md.template'
    Copy-Item -LiteralPath $mentalModelTemplatePath -Destination $mentalModelPath -Force
}

$workspaceConfig = [ordered]@{
    folders = $folders
    settings = [ordered]@{
        'chat.agentFilesLocations' = [ordered]@{
            '.github/agents' = $true
        }
        'chat.promptFilesLocations' = [ordered]@{
            '.github/prompts' = $true
        }
        'chat.agentSkillsLocations' = [ordered]@{
            '.github/skills' = $true
            '~/.copilot/skills' = $true
        }
        'chat.hookFilesLocations' = [ordered]@{
            '.github/hooks' = $true
        }
        'chat.useAgentSkills' = $true
        'chat.useAgentsMdFile' = $true
        'chat.useNestedAgentsMdFiles' = $true
        'chat.useCustomizationsInParentRepositories' = $true
    }
}

$workspaceFile = Join-Path $TargetRoot "$workspaceName.code-workspace"
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
    foreach ($workspaceRepoEntry in $workspaceRepos) {
        $additionalDirs += [string]$workspaceRepoEntry.repo_relative_path
    }

    $settings = [ordered]@{
        permissions = [ordered]@{
            additionalDirectories = $additionalDirs
        }
    }
    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath
}

$removedInstructionSummaries = Remove-HelixGeneratedInstructionSummaries -TargetRoot $TargetRoot
if ($removedInstructionSummaries -gt 0) {
    Write-Host "Removed $removedInstructionSummaries Helix-generated .instructions.md summary file(s)."
}

$skillIndexPath = Write-HelixSkillIndex -TargetRoot $TargetRoot -WorkspaceName $workspaceName -WorkspaceRepos $workspaceRepos

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
Write-Host "Updated skill registry: $skillIndexPath"

if ($crgResults.Count -gt 0) {
    Write-Host ""
    Write-Host "Code-review-graph build:"
    $crgResults | Format-Table -AutoSize
    Write-Host "Incremental updates fire automatically via the Copilot CLI subagentStop / sessionEnd hooks (helix/.github/hooks/scripts/crg-sweep.js)."
    Write-Host "Run '/hc-build-graph full' only when you need a manual repair or full refresh."
}

if (-not $SkipGraphBuild -and $crgMode -ne 'mcp') {
    Write-Host ""
    Write-Host "CRG mode is '$crgMode'. This is an emergency fallback; Helix will use default agent/search behavior. To restore graph-based retrieval, run: ./helix/scripts/set-context-provider.ps1 -Mode mcp -Bootstrap"
}
