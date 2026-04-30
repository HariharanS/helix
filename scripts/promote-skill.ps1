[CmdletBinding()]
param(
    [string]$TargetRoot = (Get-Location).Path,
    [Parameter(Mandatory = $true)][string]$SkillId,
    [string]$ProjectedName,
    [switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$indexPath = Join-Path $TargetRoot '.helix/skills/index.yml'
if (-not (Test-Path $indexPath)) {
    throw "Skill registry not found at '.helix/skills/index.yml'. Run setup-workspace.ps1 first."
}

$index = Import-HelixYamlFile -Path $indexPath
$skills = @($index.skills)
$skill = $skills | Where-Object { [string]::Equals([string]$_.id, $SkillId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
if (-not $skill) {
    throw "Skill '$SkillId' was not found in '.helix/skills/index.yml'."
}

if ($SkillId.StartsWith('hc-', [System.StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals([string]$skill.status, 'core', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Skill '$SkillId' is a Helix core skill. Core skills are promoted upstream manually, not projected with promote-skill.ps1."
}

$sourceRelative = if ($skill.origin -and $skill.origin.source_path) {
    [string]$skill.origin.source_path
} else {
    [string]$skill.path
}
$sourcePath = Join-Path $TargetRoot $sourceRelative
if (-not (Test-Path $sourcePath)) {
    throw "Source skill file for '$SkillId' does not exist: $sourceRelative"
}

$name = if ([string]::IsNullOrWhiteSpace($ProjectedName)) {
    if ([string]$SkillId -match '^hr-') {
        [string]$SkillId
    } else {
        "hr-$(ConvertTo-HelixSkillSlug -Value $SkillId)"
    }
} else {
    ConvertTo-HelixSkillSlug -Value $ProjectedName
}

if (-not $name.StartsWith('hr-', [System.StringComparison]::OrdinalIgnoreCase)) {
    $name = "hr-$name"
}

$destinationDir = Join-Path $TargetRoot ".github/skills/$name"
$destinationPath = Join-Path $destinationDir 'SKILL.md'
if ((Test-Path $destinationPath) -and -not $Force) {
    throw "Projected skill already exists at '.github/skills/$name/SKILL.md'. Re-run with -Force to overwrite it."
}

New-HelixDirectory -Path $destinationDir
$content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $sourcePath))
$content = [regex]::Replace($content, '(?m)^name:\s*.*$', "name: $name", 1)
$content = [regex]::Replace($content, '(?m)^managed-by:\s*.*$', 'managed-by: helix-runtime', 1)
if (-not $content.EndsWith("`n")) {
    $content += [Environment]::NewLine
}
[System.IO.File]::WriteAllText($destinationPath, $content)

$projectedRelative = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $destinationPath
$skill.id = $name
$skill.name = $name
$skill.status = 'projected'
$skill.path = $projectedRelative
$skill.projected_path = $projectedRelative
$skill.requires_skill_use_record = $true

$index.updated_at = (Get-Date).ToUniversalTime().ToString('o')
Write-HelixYamlFile -Path $indexPath -Value $index

[ordered]@{
    promoted_skill = $name
    source_path = $sourceRelative
    projected_path = $projectedRelative
    registry = '.helix/skills/index.yml'
} | ConvertTo-Json -Depth 6
