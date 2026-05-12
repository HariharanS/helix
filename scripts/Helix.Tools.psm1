Set-StrictMode -Version Latest

function Test-HelixScalar {
    param($Value)

    if ($null -eq $Value) { return $true }
    if ($Value -is [string] -or $Value -is [bool]) { return $true }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) { return $true }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return $true }
    return $false
}

function ConvertFrom-HelixYamlScalar {
    param([Parameter(Mandatory = $true)][string]$Text)

    $value = $Text.Trim()

    if ($value -match '^\[(.*)\]$') {
        $inner = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($inner)) {
            return @()
        }

        $parts = $inner.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $items = @()
        foreach ($part in $parts) {
            $items += ConvertFrom-HelixYamlScalar -Text $part
        }
        return ,$items
    }

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        return $value.Substring(1, $value.Length - 2)
    }

    switch -Regex ($value) {
        '^(?i:null|~)$' { return $null }
        '^(?i:true)$' { return $true }
        '^(?i:false)$' { return $false }
        '^-?\d+$' { return [int64]$value }
        '^-?\d+\.\d+$' { return [double]::Parse($value, [System.Globalization.CultureInfo]::InvariantCulture) }
        default { return $value }
    }
}

function Get-HelixYamlTokens {
    param([Parameter(Mandatory = $true)][string]$Content)

    $tokens = @()
    foreach ($rawLine in ($Content -split "`r?`n")) {
        $line = $rawLine.Replace("`t", '  ')
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $indent = [regex]::Match($line, '^ *').Value.Length
        $tokens += [pscustomobject]@{
            Indent = $indent
            Text   = $trimmed
        }
    }

    return ,$tokens
}

function Parse-HelixYamlBlock {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tokens,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][int]$Indent
    )

    if ($Index.Value -ge $Tokens.Count) {
        return $null
    }

    if ($Tokens[$Index.Value].Text.StartsWith('- ')) {
        return Parse-HelixYamlSequence -Tokens $Tokens -Index $Index -Indent $Indent
    }

    return Parse-HelixYamlMapping -Tokens $Tokens -Index $Index -Indent $Indent
}

function Parse-HelixYamlMapping {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tokens,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][int]$Indent
    )

    $map = [ordered]@{}

    while ($Index.Value -lt $Tokens.Count) {
        $token = $Tokens[$Index.Value]
        if ($token.Indent -lt $Indent) { break }
        if ($token.Indent -gt $Indent) {
            throw "Unexpected indentation while parsing mapping near '$($token.Text)'."
        }
        if ($token.Text.StartsWith('- ')) { break }

        $match = [regex]::Match($token.Text, '^(?<key>[^:]+):(?:\s*(?<value>.*))?$')
        if (-not $match.Success) {
            throw "Unsupported YAML mapping entry '$($token.Text)'."
        }

        $key = $match.Groups['key'].Value.Trim()
        $valueText = $match.Groups['value'].Value
        $Index.Value++

        if ($valueText -ne '') {
            $map[$key] = ConvertFrom-HelixYamlScalar -Text $valueText
            continue
        }

        if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $Indent) {
            $map[$key] = Parse-HelixYamlBlock -Tokens $Tokens -Index $Index -Indent $Tokens[$Index.Value].Indent
        } else {
            $map[$key] = $null
        }
    }

    return $map
}

function Parse-HelixYamlSequence {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tokens,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][int]$Indent
    )

    $items = @()

    while ($Index.Value -lt $Tokens.Count) {
        $token = $Tokens[$Index.Value]
        if ($token.Indent -lt $Indent) { break }
        if ($token.Indent -ne $Indent -or -not $token.Text.StartsWith('- ')) { break }

        $content = $token.Text.Substring(2).Trim()
        $Index.Value++

        if ([string]::IsNullOrWhiteSpace($content)) {
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $Indent) {
                $items += Parse-HelixYamlBlock -Tokens $Tokens -Index $Index -Indent $Tokens[$Index.Value].Indent
            } else {
                $items += $null
            }
            continue
        }

        $inlineMap = [regex]::Match($content, '^(?<key>[^:]+):(?:\s*(?<value>.*))?$')
        if ($inlineMap.Success) {
            $item = [ordered]@{}
            $key = $inlineMap.Groups['key'].Value.Trim()
            $valueText = $inlineMap.Groups['value'].Value
            if ($valueText -ne '') {
                $item[$key] = ConvertFrom-HelixYamlScalar -Text $valueText
            } else {
                $item[$key] = $null
            }

            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $Indent) {
                $tail = Parse-HelixYamlMapping -Tokens $Tokens -Index $Index -Indent $Tokens[$Index.Value].Indent
                foreach ($tailKey in $tail.Keys) {
                    $item[$tailKey] = $tail[$tailKey]
                }
            }

            $items += ,$item
            continue
        }

        $items += ConvertFrom-HelixYamlScalar -Text $content
    }

    return ,$items
}

function ConvertFrom-HelixYaml {
    param([Parameter(Mandatory = $true)][string]$Content)

    $tokens = Get-HelixYamlTokens -Content $Content
    if ($tokens.Count -eq 0) {
        return [ordered]@{}
    }

    $index = 0
    return Parse-HelixYamlBlock -Tokens $tokens -Index ([ref]$index) -Indent $tokens[0].Indent
}

function Import-HelixYamlFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ConvertFrom-HelixYaml -Content ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path)))
}

function Format-HelixYamlScalar {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return ($Value.ToString().ToLowerInvariant()) }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
    }
    if ($Value -is [string]) {
        if ($Value -match '^[A-Za-z0-9._/\-]+$') {
            return $Value
        }

        $escaped = $Value.Replace('"', '\"')
        return '"' + $escaped + '"'
    }

    return [string]$Value
}

function ConvertTo-HelixYamlLines {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [int]$Indent = 0
    )

    $lines = @()
    $spaces = ' ' * $Indent

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $child = $Value[$key]
            if (Test-HelixScalar -Value $child) {
                $lines += "${spaces}${key}: $(Format-HelixYamlScalar -Value $child)"
            } else {
                $lines += "${spaces}${key}:"
                $lines += ConvertTo-HelixYamlLines -Value $child -Indent ($Indent + 2)
            }
        }
        return ,$lines
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            if (Test-HelixScalar -Value $item) {
                $lines += "$spaces- $(Format-HelixYamlScalar -Value $item)"
                continue
            }

            if ($item -is [System.Collections.IDictionary]) {
                $first = $true
                foreach ($key in $item.Keys) {
                    $child = $item[$key]
                    if ($first) {
                        if (Test-HelixScalar -Value $child) {
                            $lines += "${spaces}- ${key}: $(Format-HelixYamlScalar -Value $child)"
                        } else {
                            $lines += "${spaces}- ${key}:"
                            $lines += ConvertTo-HelixYamlLines -Value $child -Indent ($Indent + 4)
                        }
                        $first = $false
                        continue
                    }

                    if (Test-HelixScalar -Value $child) {
                        $lines += "${spaces}  ${key}: $(Format-HelixYamlScalar -Value $child)"
                    } else {
                        $lines += "${spaces}  ${key}:"
                        $lines += ConvertTo-HelixYamlLines -Value $child -Indent ($Indent + 4)
                    }
                }
                continue
            }

            $lines += "$spaces-"
            $lines += ConvertTo-HelixYamlLines -Value $item -Indent ($Indent + 2)
        }
        return ,$lines
    }

    return ,@("$spaces$(Format-HelixYamlScalar -Value $Value)")
}

function Write-HelixYamlFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $content = (ConvertTo-HelixYamlLines -Value $Value) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($Path, $content + [Environment]::NewLine)
}

function New-HelixDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
}

function ConvertTo-HelixSkillSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'skill'
    }

    return $slug
}

function Import-HelixSkillFrontmatter {
    param([Parameter(Mandatory = $true)][string]$Path)

    $frontmatter = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $frontmatter
    }

    $lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        return $frontmatter
    }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -eq '---') {
            break
        }

        $match = [regex]::Match($line, '^(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*)$')
        if (-not $match.Success) {
            continue
        }

        $key = $match.Groups['key'].Value
        $value = $match.Groups['value'].Value.Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $frontmatter[$key] = $value
    }

    return $frontmatter
}

function ConvertTo-HelixRepoShortSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Cannot derive a short slug from '$Value'."
    }
    return $slug
}

function Import-HelixSkillFrontmatterYaml {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return [ordered]@{}
    }

    $lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        return [ordered]@{}
    }

    $body = New-Object System.Text.StringBuilder
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        $null = $body.AppendLine($lines[$i])
    }

    if ($body.Length -eq 0) {
        return [ordered]@{}
    }

    return ConvertFrom-HelixYaml -Content $body.ToString()
}

function Get-HelixSkillBodyContent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return ''
    }

    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    $pattern = '^---\r?\n.*?\r?\n---\r?\n?'
    $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        return $text.Substring($match.Length)
    }

    return $text
}

function Get-HelixSkillContentChecksum {
    param([Parameter(Mandatory = $true)][string]$SkillFolder)

    if (-not (Test-Path $SkillFolder)) {
        return $null
    }

    $files = Get-ChildItem -LiteralPath $SkillFolder -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $accumulator = New-Object System.IO.MemoryStream
        try {
            foreach ($file in $files) {
                $relative = (Get-HelixRelativePath -BasePath $SkillFolder -TargetPath $file.FullName)
                $headerBytes = [System.Text.Encoding]::UTF8.GetBytes("$relative`n")
                $accumulator.Write($headerBytes, 0, $headerBytes.Length)
                $contentBytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $accumulator.Write($contentBytes, 0, $contentBytes.Length)
                $accumulator.WriteByte(10)
            }
            $accumulator.Position = 0
            $hashBytes = $sha.ComputeHash($accumulator)
            $hex = ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
            return "sha256:$hex"
        } finally {
            $accumulator.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
}

function Get-HelixWorkspaceSkillSource {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRepoRoot,
        [string]$RepoShortName
    )

    $skillsRoot = Join-Path $SourceRepoRoot '.github/skills'
    if (-not (Test-Path $skillsRoot)) {
        return @()
    }

    $sources = @()
    $folders = Get-ChildItem -LiteralPath $skillsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name

    foreach ($folder in $folders) {
        $skillFile = Join-Path $folder.FullName 'SKILL.md'
        if (-not (Test-Path $skillFile)) { continue }

        $relPath = (Get-HelixRelativePath -BasePath $SourceRepoRoot -TargetPath $folder.FullName)
        $sources += [ordered]@{
            skill_name = $folder.Name
            source_folder = $folder.FullName
            source_skill_md = $skillFile
            rel_path = $relPath
            repo_short = $RepoShortName
        }
    }

    return ,$sources
}

function Set-HelixSkillFolderReadOnly {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][bool]$ReadOnly
    )

    if (-not (Test-Path $Folder)) { return }

    $files = Get-ChildItem -LiteralPath $Folder -File -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        try {
            $current = [System.IO.File]::GetAttributes($file.FullName)
            if ($ReadOnly) {
                [System.IO.File]::SetAttributes($file.FullName, $current -bor [System.IO.FileAttributes]::ReadOnly)
            } else {
                [System.IO.File]::SetAttributes($file.FullName, $current -band (-bnot [System.IO.FileAttributes]::ReadOnly))
            }
        } catch {
            # Best-effort. Some POSIX filesystems may not support the attribute; continue.
        }
    }
}

function Write-HelixSkillFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Frontmatter,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $frontmatterLines = ConvertTo-HelixYamlLines -Value $Frontmatter
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('---')
    foreach ($line in $frontmatterLines) {
        $null = $sb.AppendLine($line)
    }
    $null = $sb.AppendLine('---')
    if (-not [string]::IsNullOrEmpty($Body)) {
        $null = $sb.Append($Body)
        if (-not $Body.EndsWith("`n")) {
            $null = $sb.AppendLine()
        }
    }

    $parent = Split-Path -Parent $Path
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $sb.ToString())
}

function Publish-HelixWorkspaceSkill {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRepoRoot,
        [Parameter(Mandatory = $true)][string]$RepoShortName,
        [Parameter(Mandatory = $true)][string]$SkillRelPath,
        [Parameter(Mandatory = $true)][string]$MetaRoot
    )

    $sourceFolder = Join-Path $SourceRepoRoot $SkillRelPath
    $sourceSkillMd = Join-Path $sourceFolder 'SKILL.md'
    if (-not (Test-Path $sourceSkillMd)) {
        throw "Source skill not found at '$sourceSkillMd'."
    }

    $sourceFrontmatter = Import-HelixSkillFrontmatterYaml -Path $sourceSkillMd

    if ($sourceFrontmatter.Contains('projection')) {
        $projection = $sourceFrontmatter['projection']
        if ($projection -is [string] -and ([string]$projection).Trim() -eq 'never') {
            return $null
        }
        if ($projection -is [System.Collections.IDictionary] -and $projection.Contains('mode')) {
            if ([string]$projection['mode'] -eq 'never') {
                return $null
            }
        }
    }

    $skillFolderName = Split-Path $sourceFolder -Leaf
    $originalName = if ($sourceFrontmatter.Contains('name') -and -not [string]::IsNullOrWhiteSpace([string]$sourceFrontmatter['name'])) {
        [string]$sourceFrontmatter['name']
    } else {
        $skillFolderName
    }
    $projectedName = "$RepoShortName-$skillFolderName"

    $targetFolder = Join-Path $MetaRoot ".github/skills/$projectedName"
    $targetSkillMd = Join-Path $targetFolder 'SKILL.md'

    if (Test-Path $targetFolder) {
        $existingFrontmatter = Import-HelixSkillFrontmatterYaml -Path $targetSkillMd
        $existingProjection = $null
        if ($existingFrontmatter.Contains('projection')) {
            $existingProjection = $existingFrontmatter['projection']
        }

        $existingFromRepo = $null
        $existingFromPath = $null
        if ($existingProjection -is [System.Collections.IDictionary]) {
            if ($existingProjection.Contains('from_repo')) { $existingFromRepo = [string]$existingProjection['from_repo'] }
            if ($existingProjection.Contains('from_path')) { $existingFromPath = [string]$existingProjection['from_path'] }
        }

        if ($null -ne $existingFromRepo -and $existingFromRepo -ne $RepoShortName) {
            throw "Projection collision at '$targetFolder': already projected from repo '$existingFromRepo' (path '$existingFromPath'); refusing to overwrite with repo '$RepoShortName' (path '$SkillRelPath')."
        }
        if ($null -ne $existingFromPath -and $existingFromPath -ne $SkillRelPath) {
            throw "Projection collision at '$targetFolder': already projected from '$existingFromPath' in repo '$existingFromRepo'; refusing to overwrite with '$SkillRelPath'."
        }

        Set-HelixSkillFolderReadOnly -Folder $targetFolder -ReadOnly $false
        Remove-Item -LiteralPath $targetFolder -Recurse -Force
    }

    [System.IO.Directory]::CreateDirectory($targetFolder) | Out-Null
    Copy-Item -LiteralPath $sourceFolder -Destination $targetFolder -Recurse -Force -Container:$false
    # Copy-Item with -Container:$false copies folder *contents* into target

    $sourceChecksum = Get-HelixSkillContentChecksum -SkillFolder $sourceFolder
    $projectedAt = (Get-Date).ToUniversalTime().ToString('o')

    $newFrontmatter = [ordered]@{}
    foreach ($key in $sourceFrontmatter.Keys) {
        if ($key -eq 'name' -or $key -eq 'projection') { continue }
        $newFrontmatter[$key] = $sourceFrontmatter[$key]
    }
    $newFrontmatter['name'] = $projectedName
    $newFrontmatter['projection'] = [ordered]@{
        from_repo = $RepoShortName
        from_path = $SkillRelPath
        from_name = $originalName
        projected_at = $projectedAt
        checksum = $sourceChecksum
    }

    $body = Get-HelixSkillBodyContent -Path $sourceSkillMd
    Write-HelixSkillFile -Path $targetSkillMd -Frontmatter $newFrontmatter -Body $body

    Set-HelixSkillFolderReadOnly -Folder $targetFolder -ReadOnly $true

    return [ordered]@{
        projected_name = $projectedName
        target_folder = $targetFolder
        from_repo = $RepoShortName
        from_path = $SkillRelPath
        from_name = $originalName
        projected_at = $projectedAt
        checksum = $sourceChecksum
    }
}

function Remove-HelixWorkspaceProjection {
    param(
        [Parameter(Mandatory = $true)][string]$MetaRoot,
        [Parameter(Mandatory = $true)][string]$RepoShortName
    )

    $skillsRoot = Join-Path $MetaRoot '.github/skills'
    if (-not (Test-Path $skillsRoot)) {
        return @()
    }

    $removed = @()
    $folders = Get-ChildItem -LiteralPath $skillsRoot -Directory -ErrorAction SilentlyContinue
    foreach ($folder in $folders) {
        $folderName = $folder.Name
        if ($folderName.StartsWith('hc-', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($folderName.StartsWith('hr-', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $skillMd = Join-Path $folder.FullName 'SKILL.md'
        if (-not (Test-Path $skillMd)) { continue }

        $frontmatter = Import-HelixSkillFrontmatterYaml -Path $skillMd
        if (-not $frontmatter.Contains('projection')) { continue }
        $projection = $frontmatter['projection']
        if (-not ($projection -is [System.Collections.IDictionary])) { continue }
        if (-not $projection.Contains('from_repo')) { continue }
        if ([string]$projection['from_repo'] -ne $RepoShortName) { continue }

        Set-HelixSkillFolderReadOnly -Folder $folder.FullName -ReadOnly $false
        Remove-Item -LiteralPath $folder.FullName -Recurse -Force
        $removed += $folderName
    }

    return ,$removed
}

function Read-HelixSkillIndex {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return [ordered]@{
            schema_version = 2
            skills = @()
        }
    }

    $raw = Import-HelixYamlFile -Path $Path
    $version = if ($raw.Contains('schema_version')) { [int]$raw['schema_version'] } else { 1 }

    if ($version -ge 2) {
        return $raw
    }

    # v1 -> v2 upgrade-on-read.
    $upgraded = [ordered]@{
        schema_version = 2
    }
    foreach ($key in $raw.Keys) {
        if ($key -eq 'schema_version') { continue }
        if ($key -eq 'skills') { continue }
        $upgraded[$key] = $raw[$key]
    }

    $skills = @()
    if ($raw.Contains('skills') -and $null -ne $raw['skills']) {
        foreach ($entry in $raw['skills']) {
            if (-not ($entry -is [System.Collections.IDictionary])) { continue }
            $upgradedEntry = [ordered]@{}
            foreach ($k in $entry.Keys) {
                if ($k -eq 'routing') { continue }
                if ($k -eq 'access' -and $entry[$k] -is [System.Collections.IDictionary]) {
                    $access = [ordered]@{}
                    foreach ($ak in $entry[$k].Keys) {
                        if ($ak -eq 'host_visible') { continue }
                        $access[$ak] = $entry[$k][$ak]
                    }
                    if (-not $access.Contains('source')) {
                        $access['source'] = 'meta-root-skill'
                    }
                    $upgradedEntry[$k] = $access
                    continue
                }
                $upgradedEntry[$k] = $entry[$k]
            }
            if (-not $upgradedEntry.Contains('access')) {
                $upgradedEntry['access'] = [ordered]@{ source = 'meta-root-skill' }
            }
            $skills += ,$upgradedEntry
        }
    }
    $upgraded['skills'] = $skills

    return $upgraded
}

function Add-HelixSkillRegistryEntry {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Entries,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Ids,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Entry,
        [string]$CollisionPrefix
    )

    $candidateId = [string]$Entry.id
    if ($Ids.Contains($candidateId) -and -not [string]::IsNullOrWhiteSpace($CollisionPrefix)) {
        if ($candidateId.StartsWith('hr-', [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidateId = "hr-$CollisionPrefix-$($candidateId.Substring(3))"
        } elseif ($candidateId.StartsWith('hc-', [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidateId = "hc-$CollisionPrefix-$($candidateId.Substring(3))"
        } else {
            $candidateId = "$CollisionPrefix-$candidateId"
        }
    }

    $baseId = $candidateId
    $suffix = 2
    while ($Ids.Contains($candidateId)) {
        $candidateId = "$baseId-$suffix"
        $suffix += 1
    }

    $Entry.id = $candidateId
    $null = $Ids.Add($candidateId)
    $Entries.Add($Entry) | Out-Null
}

function Write-HelixSkillIndex {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [string]$WorkspaceName,
        [AllowEmptyCollection()][object[]]$WorkspaceRepos = @()
    )

    # WorkspaceRepos retained for back-compat with callers; workspace skills now reach
    # the index by being projected to meta-root in advance, so this scan reads only
    # the meta-root .github/skills folder and detects projection state from frontmatter.

    $skillsRoot = Join-Path $TargetRoot '.helix/skills'
    New-HelixDirectory -Path $skillsRoot
    New-HelixDirectory -Path (Join-Path $skillsRoot 'candidates')
    New-HelixDirectory -Path (Join-Path $skillsRoot 'graveyard')

    $entries = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rootSkillsDir = Join-Path $TargetRoot '.github/skills'

    if (Test-Path $rootSkillsDir) {
        $rootSkillFiles = Get-ChildItem -LiteralPath $rootSkillsDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { Join-Path $_.FullName 'SKILL.md' } |
            Where-Object { Test-Path $_ }

        foreach ($skillPath in $rootSkillFiles) {
            $skillDir = Split-Path -Parent $skillPath
            $folderName = Split-Path $skillDir -Leaf
            $frontmatterFlat = Import-HelixSkillFrontmatter -Path $skillPath
            $frontmatterFull = Import-HelixSkillFrontmatterYaml -Path $skillPath
            $skillName = if ($frontmatterFlat.Contains('name') -and -not [string]::IsNullOrWhiteSpace([string]$frontmatterFlat.name)) {
                [string]$frontmatterFlat.name
            } else {
                $folderName
            }
            $slug = ConvertTo-HelixSkillSlug -Value $skillName
            $managedBy = if ($frontmatterFlat.Contains('managed-by')) { [string]$frontmatterFlat['managed-by'] } else { '' }

            $isHrPrefixed = $folderName.StartsWith('hr-', [System.StringComparison]::OrdinalIgnoreCase)
            $isHcPrefixed = $folderName.StartsWith('hc-', [System.StringComparison]::OrdinalIgnoreCase)
            $hasProjectionBlock = $frontmatterFull.Contains('projection') -and ($frontmatterFull['projection'] -is [System.Collections.IDictionary])

            $isWorkspaceProjection = $hasProjectionBlock -and -not $isHcPrefixed -and -not $isHrPrefixed
            $isLegacyHrProjection = $isHrPrefixed -and -not $isHcPrefixed

            $id = if ($isHcPrefixed -or $isHrPrefixed) {
                ConvertTo-HelixSkillSlug -Value $folderName
            } elseif ($isWorkspaceProjection) {
                ConvertTo-HelixSkillSlug -Value $folderName
            } elseif ([string]::Equals($managedBy, 'helix-core', [System.StringComparison]::OrdinalIgnoreCase)) {
                "hc-$slug"
            } else {
                "hr-$slug"
            }

            $accessSource = if ($isWorkspaceProjection) { 'projected' }
                            elseif ($isLegacyHrProjection) { 'projected' }
                            else { 'meta-root-skill' }

            $status = if ($isWorkspaceProjection -or $isLegacyHrProjection) { 'projected' } else { 'core' }

            $entry = [ordered]@{
                id = $id
                name = $skillName
                status = $status
                access = [ordered]@{
                    source = $accessSource
                }
                origin = [ordered]@{
                    kind = if ($isWorkspaceProjection) { 'workspace-projected' }
                           elseif ($isLegacyHrProjection) { 'runtime' }
                           else { 'helix-core' }
                    source_path = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $skillPath
                }
                path = Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $skillPath
                projected_path = if ($isWorkspaceProjection -or $isLegacyHrProjection) {
                    Get-HelixRelativePath -BasePath $TargetRoot -TargetPath $skillPath
                } else { $null }
                scope = [ordered]@{
                    repos = if ($isWorkspaceProjection -and $hasProjectionBlock -and $frontmatterFull['projection'].Contains('from_repo')) {
                        @([string]$frontmatterFull['projection']['from_repo'])
                    } else { @() }
                    paths = @()
                }
                confidence = if ($isWorkspaceProjection -or $isLegacyHrProjection) { 'medium' } else { 'high' }
                description = if ($frontmatterFlat.Contains('description')) { [string]$frontmatterFlat.description } else { '' }
                requires_skill_use_record = $true
            }

            if ($isWorkspaceProjection -and $hasProjectionBlock) {
                $proj = $frontmatterFull['projection']
                $projectionEntry = [ordered]@{}
                foreach ($pk in @('from_repo', 'from_path', 'from_name', 'projected_at', 'checksum')) {
                    if ($proj.Contains($pk)) {
                        $projectionEntry[$pk] = $proj[$pk]
                    }
                }
                $entry['projection'] = $projectionEntry
            }

            Add-HelixSkillRegistryEntry -Entries $entries -Ids $ids -Entry $entry
        }
    }

    $index = [ordered]@{
        schema_version = 2
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
        active_workspace = if ([string]::IsNullOrWhiteSpace($WorkspaceName)) { $null } else { $WorkspaceName }
        skills = @($entries.ToArray())
    }

    $indexPath = Join-Path $skillsRoot 'index.yml'
    Write-HelixYamlFile -Path $indexPath -Value $index
    return $indexPath
}

function Get-HelixRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $getRelativePathMethod = [System.IO.Path].GetMethods() |
        Where-Object {
            $_.Name -eq 'GetRelativePath' -and $_.GetParameters().Count -eq 2
        } |
        Select-Object -First 1

    if ($getRelativePathMethod) {
        $relative = [string]$getRelativePathMethod.Invoke($null, @($baseFullPath, $targetFullPath))
        return $relative.Replace('\', '/')
    }

    $baseRoot = [System.IO.Path]::GetPathRoot($baseFullPath)
    $targetRoot = [System.IO.Path]::GetPathRoot($targetFullPath)
    if (-not [string]::Equals($baseRoot, $targetRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $targetFullPath.Replace('\', '/')
    }

    $baseUriPath = $baseFullPath
    if (-not $baseUriPath.EndsWith([System.IO.Path]::DirectorySeparatorChar) -and
        -not $baseUriPath.EndsWith([System.IO.Path]::AltDirectorySeparatorChar)) {
        $baseUriPath = $baseUriPath + [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = [System.Uri]::new($baseUriPath)
    $targetUri = [System.Uri]::new($targetFullPath)
    $relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())

    return $relative.Replace('\', '/')
}

function Get-HelixRoot {
    param([string]$StartPath = (Get-Location).Path)

    $current = [System.IO.Path]::GetFullPath($StartPath)
    if ([System.IO.File]::Exists($current)) {
        $current = Split-Path -Parent $current
    }

    while ($current) {
        $hasHelixDir = Test-Path (Join-Path $current '.helix')
        $hasCanonicalRegistry = Test-Path (Join-Path $current 'helix-repos.yml')
        $hasLegacyRegistry = Test-Path (Join-Path $current 'repos.yml')
        if ($hasHelixDir -or $hasCanonicalRegistry -or $hasLegacyRegistry) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current -or [string]::IsNullOrWhiteSpace($parent)) {
            break
        }
        $current = $parent
    }

    throw "Could not resolve a Helix meta-repo root from '$StartPath'."
}

function Resolve-HelixRegistryPath {
    param(
        [Parameter(Mandatory = $true)][string]$HelixRoot,
        [switch]$AllowMissing
    )

    $canonicalPath = Join-Path $HelixRoot 'helix-repos.yml'
    $legacyPath = Join-Path $HelixRoot 'repos.yml'

    if (Test-Path $canonicalPath) {
        return [ordered]@{
            path = $canonicalPath
            source = 'canonical'
            display_name = 'helix-repos.yml'
            canonical_path = $canonicalPath
            legacy_path = $legacyPath
        }
    }

    if (Test-Path $legacyPath) {
        return [ordered]@{
            path = $legacyPath
            source = 'legacy'
            display_name = 'repos.yml'
            canonical_path = $canonicalPath
            legacy_path = $legacyPath
        }
    }

    if ($AllowMissing) {
        return [ordered]@{
            path = $canonicalPath
            source = 'missing'
            display_name = 'helix-repos.yml'
            canonical_path = $canonicalPath
            legacy_path = $legacyPath
        }
    }

    throw "No helix-repos.yml found in '$HelixRoot'. Legacy fallback 'repos.yml' was also not found."
}

function Get-HelixActiveWorkspacePath {
    param([Parameter(Mandatory = $true)][string]$HelixRoot)

    $preferred = Join-Path $HelixRoot '.helix/active-workspace.yml'
    if (Test-Path $preferred) { return $preferred }

    $legacy = Join-Path $HelixRoot '.helix/active-workspace.yaml'
    if (Test-Path $legacy) { return $legacy }

    return $preferred
}

function Get-HelixWorkspaceManifestPath {
    param(
        [Parameter(Mandatory = $true)][string]$HelixRoot,
        [Parameter(Mandatory = $true)][string]$Workspace
    )

    if (Test-Path $Workspace) {
        return (Resolve-Path -LiteralPath $Workspace).Path
    }

    $preferred = Join-Path $HelixRoot "workspaces/$Workspace/workspace.yml"
    if (Test-Path $preferred) { return $preferred }

    $legacy = Join-Path $HelixRoot "workspaces/$Workspace/workspace.yaml"
    if (Test-Path $legacy) { return $legacy }

    throw "Could not find workspace manifest for '$Workspace'."
}

function Get-HelixRepoReadiness {
    param(
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $present = Test-Path $RepoPath
    $state = [ordered]@{
        schema_version = 1
        repo_id = $RepoId
        local_path = $RepoPath
        last_scanned_at = (Get-Date).ToUniversalTime().ToString('o')
        present = $present
        git = [ordered]@{
            branch = $null
            dirty = $false
            remote = $null
        }
        readiness = [ordered]@{
            state = 'missing'
            reason = 'Repo has not been attached yet'
            recommended_next_step = 'attach'
            signals = [ordered]@{
                root_agents = $false
                nested_agents = $false
                repo_skills = $false
                tests_present = $false
            }
        }
    }

    if (-not $present) {
        return $state
    }

    $rootAgents = Test-Path (Join-Path $RepoPath 'AGENTS.md')
    $nestedAgents = [bool](Get-ChildItem -Path $RepoPath -Recurse -Filter AGENTS.md -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne (Join-Path $RepoPath 'AGENTS.md') } | Select-Object -First 1)
    $repoSkills = Test-Path (Join-Path $RepoPath '.github/skills')
    $testsPresent = [bool](Get-ChildItem -Path $RepoPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('test', 'tests', 'spec', 'specs') } | Select-Object -First 1)

    $state.readiness.signals.root_agents = $rootAgents
    $state.readiness.signals.nested_agents = $nestedAgents
    $state.readiness.signals.repo_skills = $repoSkills
    $state.readiness.signals.tests_present = $testsPresent

    if (Test-Path (Join-Path $RepoPath '.git')) {
        try {
            $branch = (& git -C $RepoPath rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $state.git.branch = ($branch | Select-Object -First 1)
            }
        } catch {}

        try {
            $remote = (& git -C $RepoPath remote get-url origin 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $state.git.remote = ($remote | Select-Object -First 1)
            }
        } catch {}

        try {
            $dirty = (& git -C $RepoPath status --porcelain 2>$null)
            $state.git.dirty = [bool]$dirty
        } catch {}
    }

    if ($rootAgents) {
        $state.readiness.state = 'ready'
        $state.readiness.reason = 'Repo has baseline AGENTS.md guidance.'
        $state.readiness.recommended_next_step = 'none'
    } elseif ($nestedAgents) {
        $state.readiness.state = 'partial'
        $state.readiness.reason = 'Repo has nested AGENTS.md guidance but is missing root AGENTS.md.'
        $state.readiness.recommended_next_step = 'onboard'
    } else {
        $state.readiness.state = 'needs-onboarding'
        $state.readiness.reason = 'Repo lacks baseline Helix guidance files.'
        $state.readiness.recommended_next_step = 'onboard'
    }

    return $state
}

function Get-HelixRepoCapabilities {
    param(
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    function Test-RepoMarker {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string[]]$Candidates
        )

        foreach ($candidate in $Candidates) {
            if (Test-Path (Join-Path $Path $candidate)) {
                return $true
            }
        }

        return $false
    }

    function Find-RepoFile {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string[]]$Patterns
        )

        foreach ($pattern in $Patterns) {
            $match = Get-ChildItem -Path $Path -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }

        return $null
    }

    function Find-RepoDirectoryByName {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string[]]$Names
        )

        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $Names) {
            $null = $set.Add($name)
        }

        $match = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $set.Contains($_.Name) } |
            Select-Object -First 1

        if ($match) {
            return $match.FullName
        }

        return $null
    }

    function Add-Layer {
        param(
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Layers,
            [Parameter(Mandatory = $true)][string]$LayerId,
            [Parameter(Mandatory = $true)][string]$ExecutionScope,
            [Parameter(Mandatory = $true)][string]$Confidence,
            [string[]]$Evidence = @(),
            [string[]]$TrustNotes = @()
        )

        $Layers.Add([ordered]@{
            layer = $LayerId
            execution_scope = $ExecutionScope
            confidence = $Confidence
            evidence = @($Evidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            trust_notes = @($TrustNotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }) | Out-Null
    }

    $present = Test-Path $RepoPath
    $capabilities = [ordered]@{
        schema_version = 1
        repo_id = $RepoId
        local_path = $RepoPath
        last_scanned_at = (Get-Date).ToUniversalTime().ToString('o')
        present = $present
        language_hints = [ordered]@{
            primary = $null
            detected = @()
            confidence = 'none'
            notes = @()
        }
        build_hints = [ordered]@{
            systems = @()
            package_managers = @()
            notes = @()
        }
        verification_layers = @()
    }

    if (-not $present) {
        return $capabilities
    }

    $detectedLanguages = [System.Collections.Generic.List[string]]::new()
    $detectedBuildSystems = [System.Collections.Generic.List[string]]::new()
    $detectedPackageManagers = [System.Collections.Generic.List[string]]::new()
    $layers = [System.Collections.Generic.List[object]]::new()

    $dotnetManifest = Find-RepoFile -Path $RepoPath -Patterns @('*.sln', '*.csproj')
    if ($dotnetManifest) {
        $detectedLanguages.Add('csharp') | Out-Null
        $detectedBuildSystems.Add('dotnet') | Out-Null
        $detectedPackageManagers.Add('nuget') | Out-Null
    }

    $nodeManifest = Find-RepoFile -Path $RepoPath -Patterns @('package.json')
    if ($nodeManifest) {
        $detectedBuildSystems.Add('node') | Out-Null
        $detectedPackageManagers.Add('npm') | Out-Null
        if (Find-RepoFile -Path $RepoPath -Patterns @('tsconfig.json')) {
            $detectedLanguages.Add('typescript') | Out-Null
        } else {
            $detectedLanguages.Add('javascript') | Out-Null
        }
    }

    $pythonManifest = Find-RepoFile -Path $RepoPath -Patterns @('pyproject.toml', 'requirements.txt', 'setup.py')
    if ($pythonManifest) {
        $detectedLanguages.Add('python') | Out-Null
        $detectedBuildSystems.Add('python') | Out-Null
        $detectedPackageManagers.Add('pip') | Out-Null
    }

    $goManifest = Find-RepoFile -Path $RepoPath -Patterns @('go.mod')
    if ($goManifest) {
        $detectedLanguages.Add('go') | Out-Null
        $detectedBuildSystems.Add('go') | Out-Null
    }

    $javaManifest = Find-RepoFile -Path $RepoPath -Patterns @('pom.xml', 'build.gradle', 'build.gradle.kts')
    if ($javaManifest) {
        $detectedLanguages.Add('java') | Out-Null
        $detectedBuildSystems.Add('jvm') | Out-Null
        if ($javaManifest.EndsWith('pom.xml', [System.StringComparison]::OrdinalIgnoreCase)) {
            $detectedPackageManagers.Add('maven') | Out-Null
        } else {
            $detectedPackageManagers.Add('gradle') | Out-Null
        }
    }

    $rustManifest = Find-RepoFile -Path $RepoPath -Patterns @('Cargo.toml')
    if ($rustManifest) {
        $detectedLanguages.Add('rust') | Out-Null
        $detectedBuildSystems.Add('rust') | Out-Null
        $detectedPackageManagers.Add('cargo') | Out-Null
    }

    $buildSystems = @($detectedBuildSystems | Select-Object -Unique)
    $packageManagers = @($detectedPackageManagers | Select-Object -Unique)
    $languages = @($detectedLanguages | Select-Object -Unique)

    $capabilities.language_hints.detected = $languages
    $capabilities.language_hints.primary = if ($languages.Count -gt 0) { $languages[0] } else { $null }
    $capabilities.language_hints.confidence = if ($languages.Count -gt 0) { 'medium' } else { 'none' }
    if ($languages.Count -gt 1) {
        $capabilities.language_hints.notes = @('Multiple language markers found. Treat as polyglot repository.')
    }

    $capabilities.build_hints.systems = $buildSystems
    $capabilities.build_hints.package_managers = $packageManagers
    if ($buildSystems.Count -gt 0) {
        $capabilities.build_hints.notes = @('Build hints come from manifest file presence, not command validation.')
    }

    if ($buildSystems.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'build' -ExecutionScope 'local-runnable' -Confidence 'high' `
            -Evidence @($buildSystems) `
            -TrustNotes @('Manifest-driven detection. Actual build commands are configured per repo.')
    }

    $unitEvidence = @()
    $unitDir = Find-RepoDirectoryByName -Path $RepoPath -Names @('test', 'tests', 'spec', 'specs', '__tests__')
    if ($unitDir) { $unitEvidence += "directory:$([System.IO.Path]::GetFileName($unitDir))" }
    $unitFile = Find-RepoFile -Path $RepoPath -Patterns @('*Test*.cs', '*Tests*.csproj', 'test_*.py', '*_test.py', '*.spec.ts', '*.spec.js')
    if ($unitFile) { $unitEvidence += "file:$([System.IO.Path]::GetFileName($unitFile))" }
    if ($unitEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'unit' -ExecutionScope 'local-runnable' -Confidence 'medium' `
            -Evidence $unitEvidence `
            -TrustNotes @('Heuristic detection based on test naming conventions.')
    }

    $harnessEvidence = @()
    $harnessDir = Find-RepoDirectoryByName -Path $RepoPath -Names @('harness', 'component-tests', 'component', 'fixtures')
    if ($harnessDir) { $harnessEvidence += "directory:$([System.IO.Path]::GetFileName($harnessDir))" }
    $harnessFile = Find-RepoFile -Path $RepoPath -Patterns @('*harness*', '*component*test*')
    if ($harnessFile) { $harnessEvidence += "file:$([System.IO.Path]::GetFileName($harnessFile))" }
    if ($harnessEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'harness_component' -ExecutionScope 'local-runnable' -Confidence 'low' `
            -Evidence $harnessEvidence `
            -TrustNotes @('Name-based heuristic; may include non-verification harness assets.')
    }

    $contractEvidence = @()
    $contractDir = Find-RepoDirectoryByName -Path $RepoPath -Names @('contracts', 'contract', 'openapi', 'swagger', 'pacts')
    if ($contractDir) { $contractEvidence += "directory:$([System.IO.Path]::GetFileName($contractDir))" }
    $contractFile = Find-RepoFile -Path $RepoPath -Patterns @('*.postman_collection.json', '*pact*.json', 'openapi*.yml', 'openapi*.yaml', 'swagger*.json')
    if ($contractFile) { $contractEvidence += "file:$([System.IO.Path]::GetFileName($contractFile))" }
    if ($contractEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'contract_sandbox' -ExecutionScope 'hybrid' -Confidence 'low' `
            -Evidence $contractEvidence `
            -TrustNotes @('Contract artifacts detected; execution may require shared services or sandbox credentials.')
    }

    $integrationEvidence = @()
    $integrationDir = Find-RepoDirectoryByName -Path $RepoPath -Names @('integration', 'integration-tests', 'acceptance', 'acceptance-tests', 'smoke')
    if ($integrationDir) { $integrationEvidence += "directory:$([System.IO.Path]::GetFileName($integrationDir))" }
    $integrationFile = Find-RepoFile -Path $RepoPath -Patterns @('*IntegrationTest*', '*AcceptanceTest*', 'docker-compose*.yml', 'docker-compose*.yaml')
    if ($integrationFile) { $integrationEvidence += "file:$([System.IO.Path]::GetFileName($integrationFile))" }
    if ($integrationEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'integration_acceptance' -ExecutionScope 'hybrid' -Confidence 'medium' `
            -Evidence $integrationEvidence `
            -TrustNotes @('Integration-like assets found. Some runs may require containerized or remote dependencies.')
    }

    $uiEvidence = @()
    $uiConfig = Find-RepoFile -Path $RepoPath -Patterns @('playwright.config.*', 'cypress.config.*', 'wdio.conf.*')
    if ($uiConfig) { $uiEvidence += "file:$([System.IO.Path]::GetFileName($uiConfig))" }
    $uiDir = Find-RepoDirectoryByName -Path $RepoPath -Names @('e2e', 'ui-tests', 'playwright', 'cypress')
    if ($uiDir) { $uiEvidence += "directory:$([System.IO.Path]::GetFileName($uiDir))" }
    if ($uiEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'ui_e2e' -ExecutionScope 'local-runnable' -Confidence 'medium' `
            -Evidence $uiEvidence `
            -TrustNotes @('UI automation markers found. Browser/runtime dependencies are assumed external to this scan.')
    }

    $releaseEvidence = @()
    if (Test-RepoMarker -Path $RepoPath -Candidates @('.github/workflows', '.azuredevops', '.circleci')) {
        $releaseEvidence += 'directory:ci-pipeline-config'
    }
    $releaseFile = Find-RepoFile -Path $RepoPath -Patterns @('azure-pipelines.yml', 'Jenkinsfile', 'Dockerfile', '*.helm.yaml', '*.helm.yml')
    if ($releaseFile) { $releaseEvidence += "file:$([System.IO.Path]::GetFileName($releaseFile))" }
    if ($releaseEvidence.Count -gt 0) {
        Add-Layer -Layers $layers -LayerId 'release_qualification' -ExecutionScope 'env-backed' -Confidence 'low' `
            -Evidence $releaseEvidence `
            -TrustNotes @('Release qualification usually depends on CI/CD infra and promoted environments.')
    }

    $capabilities.verification_layers = @($layers.ToArray())
    return $capabilities
}

function Get-HelixResumeSnapshotDefault {
    param([Parameter(Mandatory = $true)][string]$WorkspaceId)

    return [ordered]@{
        schema_version = 1
        workspace = $WorkspaceId
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
        phase = [ordered]@{
            current = 'discovery'
            last_completed = $null
        }
        current_task = $null
        last_completed_task = $null
        blocked_tasks = @()
        next_action = $null
        artifact_paths = [ordered]@{
            execution_plan = $null
            task_board = $null
            decisions_log = $null
        }
        latest_sessions = @()
        verification_debt = @()
    }
}

function Merge-HelixResumeSnapshotPatch {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)]$Patch
    )

    if (-not ($Patch -is [System.Collections.IDictionary])) {
        return $Patch
    }

    if (-not ($Target -is [System.Collections.IDictionary])) {
        $Target = [ordered]@{}
    }

    foreach ($key in $Patch.Keys) {
        $patchValue = $Patch[$key]
        $hasExisting = $Target.Contains($key)
        $existingValue = if ($hasExisting) { $Target[$key] } else { $null }

        if ($patchValue -is [System.Collections.IDictionary] -and $existingValue -is [System.Collections.IDictionary]) {
            $Target[$key] = Merge-HelixResumeSnapshotPatch -Target $existingValue -Patch $patchValue
            continue
        }

        $Target[$key] = $patchValue
    }

    return $Target
}

function Update-HelixResumeSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HelixRoot,
        [Parameter(Mandatory = $true)][string]$WorkspaceId,
        [System.Collections.IDictionary]$Patch
    )

    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
        throw "Update-HelixResumeSnapshot requires a non-empty -WorkspaceId."
    }

    $resumePath = Join-Path $HelixRoot "workspaces/$WorkspaceId/resume.yml"

    if (Test-Path $resumePath) {
        $snapshot = Import-HelixYamlFile -Path $resumePath
        if (-not ($snapshot -is [System.Collections.IDictionary])) {
            $snapshot = Get-HelixResumeSnapshotDefault -WorkspaceId $WorkspaceId
        }
    } else {
        $snapshot = Get-HelixResumeSnapshotDefault -WorkspaceId $WorkspaceId
    }

    if (-not $snapshot.Contains('schema_version')) { $snapshot['schema_version'] = 1 }
    if (-not $snapshot.Contains('workspace') -or [string]::IsNullOrWhiteSpace([string]$snapshot['workspace'])) {
        $snapshot['workspace'] = $WorkspaceId
    }

    if ($null -ne $Patch -and $Patch.Count -gt 0) {
        $snapshot = Merge-HelixResumeSnapshotPatch -Target $snapshot -Patch $Patch
    }

    $snapshot['updated_at'] = (Get-Date).ToUniversalTime().ToString('o')

    Write-HelixYamlFile -Path $resumePath -Value $snapshot
    return $resumePath
}

function Merge-HelixMarkedSections {
    param(
        [Parameter(Mandatory = $true)][string]$SourceContent,
        [Parameter(Mandatory = $true)][string]$TargetContent
    )

    $pattern = '(?s)<!-- HELIX:BEGIN (?<name>[\w-]+) -->.*?<!-- HELIX:END \k<name> -->'
    $matches = [regex]::Matches($SourceContent, $pattern)
    if ($matches.Count -eq 0) {
        return $null
    }

    $merged = $TargetContent
    foreach ($match in $matches) {
        $name = $match.Groups['name'].Value
        $sectionPattern = "(?s)<!-- HELIX:BEGIN $([regex]::Escape($name)) -->.*?<!-- HELIX:END $([regex]::Escape($name)) -->"
        if (-not [regex]::IsMatch($merged, $sectionPattern)) {
            return $null
        }

        $replacement = $match.Value
        $merged = [regex]::Replace(
            $merged,
            $sectionPattern,
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },
            1
        )
    }

    return $merged
}

function Merge-HelixMarkedBlocksHash {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SourceContent,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$TargetContent
    )

    $pattern = '(?s)# HELIX:BEGIN (?<name>[\w-]+)\r?\n.*?# HELIX:END \k<name>'
    $sourceMatches = [regex]::Matches($SourceContent, $pattern)
    if ($sourceMatches.Count -eq 0) {
        return $null
    }

    $merged = $TargetContent
    foreach ($match in $sourceMatches) {
        $name = $match.Groups['name'].Value
        $sectionPattern = "(?s)# HELIX:BEGIN $([regex]::Escape($name))\r?\n.*?# HELIX:END $([regex]::Escape($name))"
        $replacement = $match.Value
        if ([regex]::IsMatch($merged, $sectionPattern)) {
            $merged = [regex]::Replace(
                $merged,
                $sectionPattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },
                1
            )
        } else {
            if ($merged.Length -gt 0 -and -not $merged.EndsWith("`n")) {
                $merged += "`r`n"
            }
            if ($merged.Length -gt 0) {
                $merged += "`r`n"
            }
            $merged += $replacement + "`r`n"
        }
    }

    return $merged
}

Export-ModuleMember -Function @(
    'ConvertFrom-HelixYaml',
    'ConvertTo-HelixRepoShortSlug',
    'ConvertTo-HelixSkillSlug',
    'ConvertTo-HelixYamlLines',
    'Get-HelixActiveWorkspacePath',
    'Get-HelixRepoCapabilities',
    'Get-HelixRelativePath',
    'Get-HelixRepoReadiness',
    'Get-HelixRoot',
    'Get-HelixSkillBodyContent',
    'Get-HelixSkillContentChecksum',
    'Get-HelixWorkspaceSkillSource',
    'Resolve-HelixRegistryPath',
    'Get-HelixWorkspaceManifestPath',
    'Import-HelixYamlFile',
    'Import-HelixSkillFrontmatter',
    'Import-HelixSkillFrontmatterYaml',
    'Merge-HelixMarkedSections',
    'Merge-HelixMarkedBlocksHash',
    'New-HelixDirectory',
    'Publish-HelixWorkspaceSkill',
    'Read-HelixSkillIndex',
    'Remove-HelixWorkspaceProjection',
    'Set-HelixSkillFolderReadOnly',
    'Update-HelixResumeSnapshot',
    'Write-HelixSkillFile',
    'Write-HelixSkillIndex',
    'Write-HelixYamlFile'
)
