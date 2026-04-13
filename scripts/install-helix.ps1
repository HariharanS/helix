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
        default {
            throw "Unsupported sync_mode '$($Item.sync_mode)' for '$($Item.path)'."
        }
    }
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$metaRepoName = Split-Path $TargetRoot -Leaf

New-HelixDirectory -Path (Join-Path $TargetRoot '.helix')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/repo-state')
New-HelixDirectory -Path (Join-Path $TargetRoot '.helix/generated')
New-HelixDirectory -Path (Join-Path $TargetRoot 'workspaces')

$items = [System.Collections.Generic.List[object]]::new()

Add-ManagedTree -Items $items -SourceRelativeRoot '.github/agents' -TargetRelativeRoot '.github/agents' -Category 'agent' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot '.github/prompts' -TargetRelativeRoot '.github/prompts' -Category 'prompt' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot '.github/skills' -TargetRelativeRoot '.github/skills' -Category 'skill' -SyncMode 'replace'

Add-ManagedFile -Items $items -SourceRelative '.github/AGENTS.md' -TargetRelative '.github/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative '.github/copilot-instructions.md' -TargetRelative '.github/copilot-instructions.md' -Category 'instruction' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative '.helix/AGENTS.md' -TargetRelative '.helix/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative '.helix/model-config.yml' -TargetRelative '.helix/model-config.yml' -Category 'config' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/AGENTS.md' -TargetRelative 'docs/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-process.md' -TargetRelative 'docs/helix-process.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'docs/helix-instance-schemas.md' -TargetRelative 'docs/helix-instance-schemas.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'workspaces/AGENTS.md' -TargetRelative 'workspaces/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot 'templates' -TargetRelativeRoot 'templates' -Category 'template' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/AGENTS.md' -TargetRelative 'scripts/AGENTS.md' -Category 'doc' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/Helix.Tools.psm1' -TargetRelative 'scripts/Helix.Tools.psm1' -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/install-helix.ps1' -TargetRelative 'scripts/install-helix.ps1' -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/set-context-provider.ps1' -TargetRelative 'scripts/set-context-provider.ps1' -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/sync-helix.ps1' -TargetRelative 'scripts/sync-helix.ps1' -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/setup-workspace.ps1' -TargetRelative 'scripts/setup-workspace.ps1' -Category 'script' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'scripts/doctor.ps1' -TargetRelative 'scripts/doctor.ps1' -Category 'script' -SyncMode 'replace'
Add-ManagedTree -Items $items -SourceRelativeRoot 'scripts/hooks' -TargetRelativeRoot 'scripts/hooks' -Category 'hook' -SyncMode 'replace'
Add-ManagedFile -Items $items -SourceRelative 'hooks/hooks.json' -TargetRelative 'hooks/hooks.json' -Category 'hook-config' -SyncMode 'replace'

Add-ManagedFile -Items $items -SourceRelative 'templates/meta-repo.README.md.template' -TargetRelative 'README.md' -Category 'doc' -SyncMode 'merge-marked-sections'
Add-ManagedFile -Items $items -SourceRelative 'templates/meta-repo.AGENTS.md.template' -TargetRelative 'AGENTS.md' -Category 'doc' -SyncMode 'merge-marked-sections'
Add-ManagedFile -Items $items -SourceRelative 'templates/mcp.json.template' -TargetRelative '.mcp.json' -Category 'config' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/repos.yml.template' -TargetRelative 'repos.yml' -Category 'manifest' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/active-workspace.yml.template' -TargetRelative '.helix/active-workspace.yml' -Category 'manifest' -SyncMode 'seed-once'
Add-ManagedFile -Items $items -SourceRelative 'templates/context-providers.yml.template' -TargetRelative '.helix/context-providers.yml' -Category 'manifest' -SyncMode 'seed-once'

foreach ($item in $items) {
    Write-ManagedFile -Item $item -MetaRepoName $metaRepoName
}

$gitKeepTargets = @(
    '.helix/repo-state/.gitkeep',
    '.helix/generated/.gitkeep',
    'workspaces/.gitkeep'
)

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
        prompts_dir = '.github/prompts'
        skills_dir = '.github/skills'
        instructions_file = '.github/copilot-instructions.md'
    }
    managed_paths = @($items.ToArray())
}

Write-HelixYamlFile -Path (Join-Path $TargetRoot '.helix/install-state.yml') -Value $installState

Write-Host "Helix installed or synced into '$TargetRoot'."
