[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Version = '0.1.0-local',
    [switch]$Force,
    [switch]$SkipDoctor,
    [switch]$SkipCRG
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

function Assert-HelixSourceRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $required = @(
        'scripts/install-helix.ps1',
        'scripts/doctor.ps1',
        'scripts/set-context-provider.ps1',
        'templates/active-workspace.yml.template',
        'templates/repo-capabilities.yml.template',
        'templates/verification-policy.yml.template'
    )

    $registryTemplateCandidates = @(
        'templates/helix-repos.yml.template',
        'templates/repos.yml.template'
    )

    $missing = @(
        $required | Where-Object {
            -not (Test-Path (Join-Path $Root $_))
        }
    )

    if ($missing.Count -gt 0) {
        throw "SourceRoot '$Root' does not look like a Helix core repo. Missing: $($missing -join ', ')"
    }

    $hasRegistryTemplate = $false
    foreach ($candidate in $registryTemplateCandidates) {
        if (Test-Path (Join-Path $Root $candidate)) {
            $hasRegistryTemplate = $true
            break
        }
    }

    if (-not $hasRegistryTemplate) {
        throw "SourceRoot '$Root' does not look like a Helix core repo. Missing one of: $($registryTemplateCandidates -join ', ')"
    }
}

function Assert-TargetRootShape {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (Test-Path $Root -PathType Leaf) {
        throw "TargetRoot '$Root' points to a file. Provide a directory path instead."
    }

    $baselineMarkers = @(
        '.helix/install-state.yml',
        '.helix',
        '.github/agents',
        'helix-repos.yml',
        'repos.yml',
        'README.md',
        'AGENTS.md'
    )

    $present = @(
        $baselineMarkers | Where-Object {
            Test-Path (Join-Path $Root $_)
        }
    )

    $hasInstallState = Test-Path (Join-Path $Root '.helix/install-state.yml')
    $hasAnyMarkers = $present.Count -gt 0

    if ($hasAnyMarkers -and -not $hasInstallState -and -not $Force) {
        throw "TargetRoot '$Root' appears partially bootstrapped without .helix/install-state.yml. Re-run with -Force after confirming you want init-meta-repo.ps1 to take ownership of the existing Helix files."
    }

    if ($hasAnyMarkers -and -not $hasInstallState -and $Force) {
        Write-Warning "TargetRoot '$Root' appears partially bootstrapped without .helix/install-state.yml. Proceeding because -Force was provided."
    }
}

function Assert-BaselineFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $required = @(
        '.helix/install-state.yml',
        '.helix/active-workspace.yml',
        '.github/agents',
        '.github/hooks',
        '.github/prompts',
        '.github/skills',
        '.github/copilot-instructions.md',
        'helix-repos.yml',
        'README.md',
        'AGENTS.md',
        'helix/README.md',
        'helix/AGENTS.md',
        'helix/docs/helix-core-meta-repo-model.md',
        'helix/docs/helix-process.md',
        'helix/docs/helix-instance-schemas.md',
        'helix/scripts/install-helix.ps1',
        'helix/scripts/set-context-provider.ps1',
        'helix/scripts/setup-workspace.ps1',
        'helix/scripts/doctor.ps1',
        'helix/templates/repo-capabilities.yml.template',
        'helix/templates/verification-policy.yml.template'
    )

    $missing = @(
        $required | Where-Object {
            -not (Test-Path (Join-Path $Root $_))
        }
    )

    if ($missing.Count -gt 0) {
        throw "Helix bootstrap completed, but required baseline paths are missing from '$Root': $($missing -join ', ')"
    }
}

function Invoke-HelixScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $powerShellPath = (Get-Process -Id $PID).Path
    & $powerShellPath -NoProfile -File $ScriptPath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path -Leaf $ScriptPath) failed with exit code $LASTEXITCODE."
    }
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)

Assert-HelixSourceRoot -Root $SourceRoot

if (-not (Test-Path $TargetRoot)) {
    New-HelixDirectory -Path $TargetRoot
}

Assert-TargetRootShape -Root $TargetRoot

$installScript = Join-Path $SourceRoot 'scripts/install-helix.ps1'
$doctorScript = Join-Path $SourceRoot 'scripts/doctor.ps1'

Write-Host "Initializing Helix meta-repo at '$TargetRoot'"

$installArguments = @(
    '-TargetRoot', $TargetRoot,
    '-SourceRoot', $SourceRoot,
    '-Version', $Version
)
if ($Force) {
    $installArguments += '-Force'
}

Invoke-HelixScript -ScriptPath $installScript -Arguments $installArguments

Assert-BaselineFiles -Root $TargetRoot

$contextProviderScript = Join-Path $SourceRoot 'scripts/set-context-provider.ps1'
if (-not (Test-Path $contextProviderScript)) {
    throw "Cannot configure code-review-graph: '$contextProviderScript' not found."
}

if ($SkipCRG) {
    Write-Warning "Skipping code-review-graph bootstrap (-SkipCRG). This is an emergency fallback; Helix will use default agent/search behavior until CRG is re-enabled."
    Invoke-HelixScript -ScriptPath $contextProviderScript -Arguments @(
        '-TargetRoot', $TargetRoot,
        '-Provider', 'code-review-graph',
        '-Mode', 'off',
        '-SuppressNextSteps'
    )
} else {
    Write-Host "Bootstrapping required code-review-graph MCP provider..."
    Invoke-HelixScript -ScriptPath $contextProviderScript -Arguments @(
        '-TargetRoot', $TargetRoot,
        '-Provider', 'code-review-graph',
        '-Mode', 'mcp',
        '-Bootstrap',
        '-SuppressNextSteps'
    )
}

if (-not $SkipDoctor) {
    Invoke-HelixScript -ScriptPath $doctorScript -Arguments @('-TargetRoot', $TargetRoot)
}

Write-Host "Helix meta-repo initialized successfully at '$TargetRoot'."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Open '$TargetRoot\README.md' for the setup checklist."
Write-Host "2. Update '$TargetRoot\helix-repos.yml' with real repos."
Write-Host "3. From the meta repo root, run workspace setup. Example:"
Write-Host "   .\helix\scripts\workspace-setup.ps1 -Workspace <workspace-id> -ReposCsv `"repo-a,repo-b`" -CloneMissing"
Write-Host "4. After workspace setup is ready, start '@setup' or '@helix' from the meta repo root as described in README.md."
