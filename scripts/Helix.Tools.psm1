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

function Get-HelixRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $relative = [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($BasePath),
        [System.IO.Path]::GetFullPath($TargetPath)
    )

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
                instructions = $false
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
    $instructions = Test-Path (Join-Path $RepoPath '.github/instructions')
    $repoSkills = Test-Path (Join-Path $RepoPath '.github/skills')
    $testsPresent = [bool](Get-ChildItem -Path $RepoPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('test', 'tests', 'spec', 'specs') } | Select-Object -First 1)

    $state.readiness.signals.root_agents = $rootAgents
    $state.readiness.signals.nested_agents = $nestedAgents
    $state.readiness.signals.instructions = $instructions
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

    if ($rootAgents -and ($instructions -or $nestedAgents)) {
        $state.readiness.state = 'ready'
        $state.readiness.reason = 'Repo has baseline agent guidance and discoverable conventions.'
        $state.readiness.recommended_next_step = 'none'
    } elseif ($rootAgents -or $instructions -or $nestedAgents) {
        $state.readiness.state = 'partial'
        $state.readiness.reason = 'Repo has some Helix signals but still needs onboarding or refresh.'
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
            [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]]$Layers,
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

Export-ModuleMember -Function @(
    'ConvertFrom-HelixYaml',
    'ConvertTo-HelixYamlLines',
    'Get-HelixActiveWorkspacePath',
    'Get-HelixRepoCapabilities',
    'Get-HelixRelativePath',
    'Get-HelixRepoReadiness',
    'Get-HelixRoot',
    'Resolve-HelixRegistryPath',
    'Get-HelixWorkspaceManifestPath',
    'Import-HelixYamlFile',
    'Merge-HelixMarkedSections',
    'New-HelixDirectory',
    'Write-HelixYamlFile'
)
