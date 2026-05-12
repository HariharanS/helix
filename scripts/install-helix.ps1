[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Version = '0.1.0-local',
    [switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

function Add-ManagedFile {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [string]$SourceRelative,
        [string]$TargetRelative,
        [string]$Category,
        [string]$SyncMode,
        [bool]$Required = $true
    )

    if ([string]::IsNullOrWhiteSpace($SourceRelative)) {
        throw "Managed file source path cannot be empty for target '$TargetRelative' ($Category)."
    }
    if ([string]::IsNullOrWhiteSpace($TargetRelative)) {
        throw "Managed file target path cannot be empty for source '$SourceRelative' ($Category)."
    }

    $Items.Add([ordered]@{
        path = $TargetRelative.Replace('\', '/')
        source = $SourceRelative.Replace('\', '/')
        category = $Category
        sync_mode = $SyncMode
        required = $Required
    }) | Out-Null
}

function Add-ManagedTree {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [string]$SourceRelativeRoot,
        [string]$TargetRelativeRoot,
        [string]$Category,
        [string]$SyncMode
    )

    $sourceDir = Join-Path $SourceRoot $SourceRelativeRoot
    if (-not (Test-Path $sourceDir)) { return }

    Get-ChildItem -Path $sourceDir -Recurse -File | ForEach-Object {
        $sourceRelative = Get-HelixRelativePath -BasePath $SourceRoot -TargetPath $_.FullName
        $subPath = Get-HelixRelativePath -BasePath $sourceDir -TargetPath $_.FullName
        if ([string]::IsNullOrWhiteSpace($subPath)) {
            throw "Managed tree '$SourceRelativeRoot' produced an empty relative path for '$($_.FullName)'."
        }
        $targetRelative = (Join-Path $TargetRelativeRoot $subPath).Replace('\', '/')
        Add-ManagedFile -Items $Items -SourceRelative $sourceRelative -TargetRelative $targetRelative -Category $Category -SyncMode $SyncMode
    }
}

function Write-ManagedFile {
    param(
        [System.Collections.IDictionary]$Item,
        [string]$MetaRepoName
    )

    $targetPath = Join-Path $TargetRoot $Item.path
    $targetDir = Split-Path -Parent $targetPath
    if ($targetDir) {
        New-HelixDirectory -Path $targetDir
    }

    switch ($Item.sync_mode) {
        'replace' {
            $sourcePath = Join-Path $SourceRoot $Item.source
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }
        'seed-once' {
            if ($Force -or -not (Test-Path $targetPath)) {
                $sourcePath = Join-Path $SourceRoot $Item.source
                Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
            }
        }
        'merge-marked-sections' {
            $sourcePath = Join-Path $SourceRoot $Item.source
            $sourceContent = [System.IO.File]::ReadAllText($sourcePath).Replace('{{META_REPO_NAME}}', $MetaRepoName)

            if (-not (Test-Path $targetPath)) {
                [System.IO.File]::WriteAllText($targetPath, $sourceContent)
                break
            }

            $targetContent = [System.IO.File]::ReadAllText($targetPath)
            $merged = Merge-HelixMarkedSections -SourceContent $sourceContent -TargetContent $targetContent
            if ($null -eq $merged) {
                if ($Force) {
                    [System.IO.File]::WriteAllText($targetPath, $sourceContent)
                    break
                }
                Write-Warning "Skipping merge for '$($Item.path)' because the target file does not contain the expected HELIX markers."
                break
            }

            [System.IO.File]::WriteAllText($targetPath, $merged)
        }
        'append-marked-block-hash' {
            $sourcePath = Join-Path $SourceRoot $Item.source
            $sourceContent = [System.IO.File]::ReadAllText($sourcePath)

            if (-not (Test-Path $targetPath)) {
                [System.IO.File]::WriteAllText($targetPath, $sourceContent)
                break
            }

            $targetContent = [System.IO.File]::ReadAllText($targetPath)
            $merged = Merge-HelixMarkedBlocksHash -SourceContent $sourceContent -TargetContent $targetContent
            if ($null -eq $merged) {
                Write-Warning "Skipping merge for '$($Item.path)' because the source has no '# HELIX:BEGIN' blocks."
                break
            }

            [System.IO.File]::WriteAllText($targetPath, $merged)
        }
        default {
            throw "Unsupported sync_mode '$($Item.sync_mode)' for '$($Item.path)'."
        }
    }
}

function Remove-StaleManagedPath {
    param([string]$RelativePath)

    $targetPath = Join-Path $TargetRoot $RelativePath
    if (-not (Test-Path $targetPath)) {
        return
    }

    Remove-Item -LiteralPath $targetPath -Force -Recurse

    $parent = Split-Path -Parent $targetPath
    while ($parent -and (Test-Path $parent) -and $parent -ne $TargetRoot) {
        $children = @(Get-ChildItem -LiteralPath $parent -Force)
        if ($children.Count -gt 0) {
            break
        }

        Remove-Item -LiteralPath $parent -Force
        $parent = Split-Path -Parent $parent
    }
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$metaRepoName = Split-Path $TargetRoot -Leaf
$existingInstallStatePath = Join-Path $TargetRoot '.helix/install-state.yml'
$canonicalRegistryPath = Join-Path $TargetRoot 'helix-repos.yml'
$legacyRegistryPath = Join-Path $TargetRoot 'repos.yml'
$previousManagedPaths = @()

if (Test-Path $existingInstallStatePath) {
    try {
        $existingInstallState = Import-HelixYamlFile -Path $existingInstallStatePath
        if ($existingInstallState.managed_paths) {
            $previousManagedPaths = @($existingInstallState.managed_paths | ForEach-Object { [string]$_.path })
        }
    } catch {
        Write-Warning "Unable to read existing install state at '$existingInstallStatePath'. Stale managed-path cleanup will be skipped."
    }
}

New-HelixDirectory -Path (Join-Path $TargetRoot '.helix')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/repo-state')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/repo-capabilities')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/generated')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/skills')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/skills/candidates')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/skills/graveyard')
New-HelixDirectory -Path (Join-Path $TargetRoot 'workspaces')

if (-not (Test-Path $canonicalRegistryPath) -and (Test-Path $legacyRegistryPath)) {
    Copy-Item -LiteralPath $legacyRegistryPath -Destination $canonicalRegistryPath -Force
    Write-Warning "Migrated legacy registry manifest 'repos.yml' to canonical 'helix-repos.yml'."
}

$managedAssetRoot = 'helix'

$items = [System.Collections.Generic.List[object]]::new()

Add-ManagedTree -Items $items -SourceRelativeRoot '.github/agents' -TargetRelativeRoot '.github/agents' -Category 'agent' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot '.github/hooks' -TargetRelativeRoot '.github/hooks' -Category 'hook-config' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot '.github/prompts' -TargetRelativeRoot '.github/prompts' -Category 'prompt' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot '.github/skills' -TargetRelativeRoot '.github/skills' -Category 'skill' -SyncMode 'replace'

Add-ManagedFile -Items $items -SourceRelative '.github/AGENTS.md' -TargetRelative '.github/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative '.helix/AGENTS.md' -TargetRelative '.helix/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative '.helix/model-config.yml' -TargetRelative '.helix/model-config.yml' -Category 'config' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'README.md' -TargetRelative (Join-Path $managedAssetRoot 'README.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'AGENTS.md' -TargetRelative (Join-Path $managedAssetRoot 'AGENTS.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/AGENTS.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/AGENTS.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-core-meta-repo-model.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/helix-core-meta-repo-model.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-process.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/helix-process.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-instance-schemas.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/helix-instance-schemas.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/cli-workflow.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/cli-workflow.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/starting-cross-repo-feature-with-helix.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/starting-cross-repo-feature-with-helix.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-platform-roadmap.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/helix-platform-roadmap.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/agents-md-authoring.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/agents-md-authoring.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/agents-md-implementation-handover.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/agents-md-implementation-handover.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/meta-repo-skills-management.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/meta-repo-skills-management.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/hc-hr-runtime-surface-rename-plan.md' -TargetRelative (Join-Path $managedAssetRoot 'docs/hc-hr-runtime-surface-rename-plan.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'workspaces/AGENTS.md' -TargetRelative 'workspaces/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot 'templates' -TargetRelativeRoot (Join-Path $managedAssetRoot 'templates') -Category 'template' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/AGENTS.md' -TargetRelative (Join-Path $managedAssetRoot 'scripts/AGENTS.md') -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/Helix.Tools.psm1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/Helix.Tools.psm1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/init-meta-repo.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/init-meta-repo.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/install-helix.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/install-helix.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/set-context-provider.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/set-context-provider.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/sync-helix.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/sync-helix.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/setup-workspace.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/setup-workspace.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/doctor.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/doctor.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/init.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/init.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/sync.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/sync.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/upgrade.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/upgrade.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/workspace-setup.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/workspace-setup.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/resolve-skill.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/resolve-skill.ps1') -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/promote-skill.ps1' -TargetRelative (Join-Path $managedAssetRoot 'scripts/promote-skill.ps1') -Category 'script' -SyncMode 'replace'

# Pet (always-on-top WPF + WebView2 companion). Spawned by .github/hooks/scripts/pet-spawn.js
# on Copilot sessionStart and resolved at <meta-root>/pet/. WebView2 lib DLLs auto-fetch
# on first launch; runtime artifacts (lib/, *.log, *.pid) are gitignored in source.
Add-ManagedFile -Items $items -SourceRelative 'pet/pet-host.ps1' -TargetRelative 'pet/pet-host.ps1' -Category 'pet' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'pet/README.md' -TargetRelative 'pet/README.md' -Category 'pet' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot 'pet/content' -TargetRelativeRoot 'pet/content' -Category 'pet' -SyncMode 'replace'

Add-ManagedFile -Items $items -SourceRelative 'templates/meta-repo.README.md.template' -TargetRelative 'README.md' -Category 'doc' -SyncMode 'merge-marked-sections'
Add-ManagedFile -Items $items -SourceRelative 'templates/meta-repo.AGENTS.md.template' -TargetRelative 'AGENTS.md' -Category 'doc' -SyncMode 'merge-marked-sections'
Add-ManagedFile -Items $items -SourceRelative 'templates/vscode.mcp.json.template' -TargetRelative '.vscode/mcp.json' -Category 'config' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/helix-repos.yml.template' -TargetRelative 'helix-repos.yml' -Category 'manifest' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/active-workspace.yml.template' -TargetRelative '.helix/active-workspace.yml' -Category 'manifest' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/context-providers.yml.template' -TargetRelative '.helix/context-providers.yml' -Category 'manifest' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/meta-repo.gitignore.template' -TargetRelative '.gitignore' -Category 'config' -SyncMode 'append-marked-block-hash'

$gitKeepTargets = @(
    '.helix/repo-state/.gitkeep',
    '.helix/repo-capabilities/.gitkeep',
    '.helix/generated/.gitkeep',
    '.helix/skills/candidates/.gitkeep',
    '.helix/skills/graveyard/.gitkeep',
    'workspaces/.gitkeep'
)

$currentManagedPathSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($managedItem in $items) {
    $null = $currentManagedPathSet.Add([string]$managedItem.path)
}
foreach ($gitKeep in $gitKeepTargets) {
    $null = $currentManagedPathSet.Add($gitKeep.Replace('\', '/'))
}

$staleManagedPaths = @(
    $previousManagedPaths | Where-Object {
        -not $currentManagedPathSet.Contains($_)
    }
)

$legacyManagedRoots = @('docs/', 'scripts/', 'templates/')
$legacyManagedUpgradePaths = @(
    $staleManagedPaths | Where-Object {
        $normalized = ([string]$_).Replace('\', '/')
        $legacyManagedRoots | Where-Object { $normalized.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
    }
)

if ($legacyManagedUpgradePaths.Count -gt 0) {
    Write-Warning "Helix upgrade is removing legacy managed root assets from docs/, scripts/, and templates/; managed assets now live under helix/."
}

foreach ($previousPath in $staleManagedPaths) {
    if ([string]::Equals([string]$previousPath, '.mcp.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "Leaving legacy '.mcp.json' in place. MCP config is now host-specific: use '.vscode/mcp.json' for VS Code and '~/.copilot/mcp-config.json' for Copilot CLI."
        continue
    }

    Remove-StaleManagedPath -RelativePath $previousPath
}

foreach ($item in $items) {
    Write-ManagedFile -Item $item -MetaRepoName $metaRepoName
}

$skillIndexPath = Write-HelixSkillIndex -TargetRoot $TargetRoot

foreach ($gitKeep in $gitKeepTargets) {
    $absolute = Join-Path $TargetRoot $gitKeep
    $dir = Split-Path -Parent $absolute
    New-HelixDirectory -Path $dir
    if (-not (Test-Path $absolute)) {
        [System.IO.File]::WriteAllText($absolute, '')
    }

    $items.Add([ordered]@{
        path = $gitKeep.Replace('\', '/')
        source = 'internal/.gitkeep'
        category = 'support'
        sync_mode = 'seed-once'
        required = $true
    }) | Out-Null
}

$sourceReference = if ([System.IO.Path]::IsPathRooted($SourceRoot)) {
    Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $SourceRoot
} else {
    $SourceRoot
}

$installState = [ordered]@{
    schema_version = 1
    helix_core = [ordered]@{
        kind = 'local-path'
        source = $sourceReference
        version = $Version
    }
    installed_at = (Get-Date).ToUniversalTime().ToString('o')
    last_sync_at = (Get-Date).ToUniversalTime().ToString('o')
    runtime_surface = [ordered]@{
        agents_dir = '.github/agents'
        hooks_dir = '.github/hooks'
        prompts_dir = '.github/prompts'
        skills_dir = '.github/skills'
        agent_guidance_file = 'AGENTS.md'
        skill_registry_file = '.helix/skills/index.yml'
    }
    managed_paths = @($items.ToArray())
}

Write-HelixYamlFile -Path (Join-Path $TargetRoot '.helix/install-state.yml') -Value $installState

Write-Host "Helix installed or synced into '$TargetRoot'."
Write-Host "Updated skill registry: $skillIndexPath"
