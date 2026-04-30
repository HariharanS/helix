[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [string]$RepoId,
    [string]$Path,
    [string]$Task,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

function Test-HelixRepoMatch {
    param(
        [Parameter(Mandatory = $true)]$Skill,
        [string]$RepoId
    )

    if ([string]::IsNullOrWhiteSpace($RepoId)) {
        return $false
    }

    if ($Skill.origin -and $Skill.origin.repo_id -and [string]::Equals([string]$Skill.origin.repo_id, $RepoId, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($Skill.scope -and $Skill.scope.repos) {
        foreach ($repo in @($Skill.scope.repos)) {
            if ([string]::Equals([string]$repo, $RepoId, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }

    return $false
}

function Test-HelixPathMatch {
    param(
        [Parameter(Mandatory = $true)]$Skill,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not $Skill.scope -or -not $Skill.scope.paths) {
        return $false
    }

    $normalizedPath = $Path.Replace('\', '/')
    foreach ($pattern in @($Skill.scope.paths)) {
        $normalizedPattern = ([string]$pattern).Replace('\', '/')
        if ($normalizedPath -like $normalizedPattern) {
            return $true
        }
    }

    return $false
}

function Get-HelixTaskMatchScore {
    param(
        [Parameter(Mandatory = $true)]$Skill,
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return 0
    }

    $haystack = @(
        [string]$Skill.id,
        [string]$Skill.name,
        [string]$Skill.description
    ) -join ' '
    $haystack = $haystack.ToLowerInvariant()

    $score = 0
    $tokens = $Task.ToLowerInvariant() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique
    foreach ($token in $tokens) {
        if ($haystack.Contains($token)) {
            $score += 5
        }
    }

    return $score
}

function Get-HelixStatusPriority {
    param([string]$Status)

    switch ($Status) {
        'projected' { return 3 }
        'candidate' { return 2 }
        'core' { return 1 }
        default { return 0 }
    }
}

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$indexPath = Join-Path $TargetRoot '.helix/skills/index.yml'

if (-not (Test-Path $indexPath)) {
    $result = [ordered]@{
        skill_use = [ordered]@{
            task_repo = $RepoId
            selected_skill = $null
            source_path = $null
            status = 'no_registry'
            fallback = 'none'
            selection_reason = "No skill registry found at .helix/skills/index.yml."
        }
    }
    $result | ConvertTo-Json -Depth 8
    exit 0
}

$index = Import-HelixYamlFile -Path $indexPath
$scored = @()

foreach ($skill in @($index.skills)) {
    $repoMatch = Test-HelixRepoMatch -Skill $skill -RepoId $RepoId
    $pathMatch = Test-HelixPathMatch -Skill $skill -Path $Path
    $taskScore = Get-HelixTaskMatchScore -Skill $skill -Task $Task
    $statusPriority = Get-HelixStatusPriority -Status ([string]$skill.status)

    $score = 0
    if ($repoMatch) { $score += 100 }
    if ($pathMatch) { $score += 20 }
    $score += $taskScore
    if ($score -gt 0) { $score += $statusPriority }

    if ($score -gt 0) {
        $scored += [pscustomobject]@{
            Skill = $skill
            Score = $score
            StatusPriority = $statusPriority
            RepoMatch = $repoMatch
            PathMatch = $pathMatch
            TaskScore = $taskScore
        }
    }
}

if ($scored.Count -eq 0) {
    $result = [ordered]@{
        skill_use = [ordered]@{
            task_repo = $RepoId
            selected_skill = $null
            source_path = $null
            status = 'no_match'
            fallback = 'none'
            selection_reason = 'No skill matched the repo, path, or task.'
        }
    }
    $result | ConvertTo-Json -Depth 8
    exit 0
}

$ranked = @($scored | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'StatusPriority'; Descending = $true }, @{ Expression = { [string]$_.Skill.id }; Descending = $false })
$top = $ranked[0]
$ties = @($ranked | Where-Object { $_.Score -eq $top.Score -and $_.StatusPriority -eq $top.StatusPriority })

if ($ties.Count -gt 1) {
    $result = [ordered]@{
        skill_use = [ordered]@{
            task_repo = $RepoId
            selected_skill = $null
            source_path = $null
            status = 'needs_disambiguation'
            fallback = 'none'
            selection_reason = 'Multiple skills matched with the same score and priority.'
            candidates = @($ties | ForEach-Object { [string]$_.Skill.id })
        }
    }
    $result | ConvertTo-Json -Depth 8
    exit 0
}

$selected = $top.Skill
$sourcePath = if ($selected.projected_path) {
    [string]$selected.projected_path
} elseif ($selected.origin -and $selected.origin.source_path) {
    [string]$selected.origin.source_path
} else {
    [string]$selected.path
}

$fallback = switch ([string]$selected.status) {
    'candidate' { 'repo-local' }
    'projected' { 'projected' }
    'core' { 'core' }
    default { 'unknown' }
}

$reasonParts = @()
if ($top.RepoMatch) { $reasonParts += 'repo matched' }
if ($top.PathMatch) { $reasonParts += 'path matched' }
if ($top.TaskScore -gt 0) { $reasonParts += 'task text matched' }

$result = [ordered]@{
    skill_use = [ordered]@{
        task_repo = $RepoId
        selected_skill = [string]$selected.id
        source_path = $sourcePath
        status = [string]$selected.status
        fallback = $fallback
        selection_reason = if ($reasonParts.Count -gt 0) { $reasonParts -join '; ' } else { 'matched by registry score' }
    }
}

$result | ConvertTo-Json -Depth 8
