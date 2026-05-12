[CmdletBinding(DefaultParameterSetName = 'Set')]
param(
    [ValidateSet('code-review-graph')][string]$Provider = 'code-review-graph',
    [Parameter(ParameterSetName = 'Set', Mandatory = $true)]
    [ValidateSet('off', 'mcp')][string]$Mode,
    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,
    [switch]$Bootstrap,
    [switch]$SuppressNextSteps,
    [string]$TargetRoot = (Get-Location).Path
)

Import-Module (Join-Path $PSScriptRoot 'Helix.Tools.psm1') -Force

function Get-DefaultContextProvidersConfig {
    return [ordered]@{
        schema_version = 1
        providers = [ordered]@{
            code_review_graph = [ordered]@{
                mode = 'off'
                detail_level = 'minimal'
                max_tool_calls_per_task = 10
                max_context_tokens_per_task = 4000
            }
        }
    }
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

function Get-VerifiedCodeReviewGraphServer {
    if (Get-Command uvx -ErrorAction SilentlyContinue) {
        return [ordered]@{
            command = 'uvx'
            args = @('code-review-graph', 'serve')
        }
    }

    if (Get-Command code-review-graph -ErrorAction SilentlyContinue) {
        return [ordered]@{
            command = 'code-review-graph'
            args = @('serve')
        }
    }

    if ((Get-Command python -ErrorAction SilentlyContinue) -and
        (Test-CodeReviewGraphPythonModule -Command 'python' -Arguments @('-c', 'import code_review_graph'))) {
        return [ordered]@{
            command = 'python'
            args = @('-m', 'code_review_graph', 'serve')
        }
    }

    if ((Get-Command py -ErrorAction SilentlyContinue) -and
        (Test-CodeReviewGraphPythonModule -Command 'py' -Arguments @('-3', '-c', 'import code_review_graph'))) {
        return [ordered]@{
            command = 'py'
            args = @('-3', '-m', 'code_review_graph', 'serve')
        }
    }

    return $null
}

function Install-CodeReviewGraphRuntime {
    $server = Get-VerifiedCodeReviewGraphServer
    if ($null -ne $server) {
        return $server
    }

    if (Get-Command pipx -ErrorAction SilentlyContinue) {
        Write-Host "Installing code-review-graph with pipx..."
        & pipx install code-review-graph
        if ($LASTEXITCODE -ne 0) {
            throw "pipx install code-review-graph failed."
        }
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "Installing code-review-graph with python -m pip --user..."
        & python -m pip install --user code-review-graph
        if ($LASTEXITCODE -ne 0) {
            throw "python -m pip install --user code-review-graph failed."
        }
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        Write-Host "Installing code-review-graph with py -3 -m pip --user..."
        & py -3 -m pip install --user code-review-graph
        if ($LASTEXITCODE -ne 0) {
            throw "py -3 -m pip install --user code-review-graph failed."
        }
    } else {
        throw "Could not bootstrap code-review-graph automatically. Install one of: uvx, pipx, python + pip, or py + pip."
    }

    $server = Get-VerifiedCodeReviewGraphServer
    if ($null -eq $server) {
        throw "code-review-graph installation completed, but no portable runtime was detected. Re-open your shell or add the installed command to PATH, then run set-context-provider.ps1 again."
    }

    return $server
}

function ConvertTo-ConfigHashtable {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[$key] = ConvertTo-ConfigHashtable -Value $Value[$key]
        }
        return $result
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-ConfigHashtable -Value $property.Value
        }
        return $result
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ConvertTo-ConfigHashtable -Value $item
        }
        return ,$items
    }

    return $Value
}

function Ensure-ContextProvidersConfig {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config)

    if (-not $Config.Contains('schema_version')) {
        $Config['schema_version'] = 1
    }

    if (-not $Config.Contains('providers') -or $null -eq $Config['providers']) {
        $Config['providers'] = [ordered]@{}
    }

    if (-not $Config['providers'].Contains('code_review_graph') -or $null -eq $Config['providers']['code_review_graph']) {
        $Config['providers']['code_review_graph'] = [ordered]@{}
    }

    $providerConfig = $Config['providers']['code_review_graph']
    if (-not $providerConfig.Contains('mode')) {
        $providerConfig['mode'] = 'off'
    }
    if (-not $providerConfig.Contains('detail_level')) {
        $providerConfig['detail_level'] = 'minimal'
    }
    if (-not $providerConfig.Contains('max_tool_calls_per_task')) {
        $providerConfig['max_tool_calls_per_task'] = 10
    }
    if (-not $providerConfig.Contains('max_context_tokens_per_task')) {
        $providerConfig['max_context_tokens_per_task'] = 4000
    }

    return $Config
}

function Read-McpConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return [ordered]@{
            mcpServers = [ordered]@{}
        }
    }

    try {
        $config = ConvertTo-ConfigHashtable -Value (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        throw "Could not parse MCP config at '$Path'. Fix the JSON first."
    }

    if (-not $config.Contains('mcpServers') -or $null -eq $config['mcpServers']) {
        $config['mcpServers'] = [ordered]@{}
    }

    return $config
}

function Read-VSCodeMcpConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return [ordered]@{
            inputs = @()
            servers = [ordered]@{}
        }
    }

    try {
        $config = ConvertTo-ConfigHashtable -Value (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        throw "Could not parse VS Code MCP config at '$Path'. Fix the JSON first."
    }

    if (-not $config.Contains('inputs') -or $null -eq $config['inputs']) {
        $config['inputs'] = @()
    }

    if (-not $config.Contains('servers') -or $null -eq $config['servers']) {
        $config['servers'] = [ordered]@{}
    }

    return $config
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-McpConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config
    )

    Ensure-ParentDirectory -Path $Path
    $json = $Config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine)
}

function Write-VSCodeMcpConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config
    )

    Ensure-ParentDirectory -Path $Path
    $json = $Config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine)
}

function Convert-ToCliMcpServerConfig {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Server)

    $config = [ordered]@{
        type = 'stdio'
        command = [string]$Server['command']
        args = @($Server['args'])
        tools = @('*')
    }

    if ($Server.Contains('env') -and $Server['env']) {
        $config['env'] = $Server['env']
    }

    return $config
}

function Convert-ToVSCodeMcpServerConfig {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Server)

    $config = [ordered]@{
        command = [string]$Server['command']
    }

    if ($Server.Contains('args') -and $Server['args']) {
        $config['args'] = @($Server['args'])
    }

    if ($Server.Contains('env') -and $Server['env']) {
        $config['env'] = $Server['env']
    }

    return $config
}

function Show-CodeReviewGraphStatus {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$CliMcpConfig,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$VSCodeMcpConfig,
        [bool]$LegacyProjectConfigContainsServer = $false
    )

    $providerConfig = $Config['providers']['code_review_graph']
    $mode = [string]$providerConfig['mode']
    $detailLevel = [string]$providerConfig['detail_level']
    $maxToolCalls = [string]$providerConfig['max_tool_calls_per_task']
    $maxContextTokens = [string]$providerConfig['max_context_tokens_per_task']
    $cliServer = $null
    $vscodeServer = $null

    if ($CliMcpConfig['mcpServers'].Contains('code-review-graph')) {
        $cliServer = $CliMcpConfig['mcpServers']['code-review-graph']
    }

    if ($VSCodeMcpConfig['servers'].Contains('code-review-graph')) {
        $vscodeServer = $VSCodeMcpConfig['servers']['code-review-graph']
    }

    Write-Host "Provider: code-review-graph"
    Write-Host "Mode: $mode"
    Write-Host "Detail level: $detailLevel"
    Write-Host "Budget: $maxToolCalls calls, $maxContextTokens tokens per task"

    if ($null -ne $cliServer) {
        $args = if ($cliServer.Contains('args') -and $cliServer['args']) { [string]::Join(' ', $cliServer['args']) } else { '' }
        Write-Host "CLI MCP: configured ($($cliServer['command']) $args)".TrimEnd()
    } else {
        Write-Host "CLI MCP: not configured"
    }

    if ($null -ne $vscodeServer) {
        $args = if ($vscodeServer.Contains('args') -and $vscodeServer['args']) { [string]::Join(' ', $vscodeServer['args']) } else { '' }
        Write-Host "VS Code MCP: configured ($($vscodeServer['command']) $args)".TrimEnd()
    } else {
        Write-Host "VS Code MCP: not configured"
    }

    if ($LegacyProjectConfigContainsServer) {
        Write-Host "Legacy root .mcp.json: contains code-review-graph (migration pending)"
    }
}

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$configPath = Join-Path $TargetRoot '.helix/context-providers.yml'
$legacyProjectMcpPath = Join-Path $TargetRoot '.mcp.json'
$vscodeMcpPath = Join-Path $TargetRoot '.vscode/mcp.json'
$cliMcpPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot/mcp-config.json'
$legacyProjectMcpPathExists = Test-Path $legacyProjectMcpPath
$vscodeMcpPathExists = Test-Path $vscodeMcpPath
$cliMcpPathExists = Test-Path $cliMcpPath

$contextProvidersConfig =
    if (Test-Path $configPath) {
        Ensure-ContextProvidersConfig -Config (Import-HelixYamlFile -Path $configPath)
    } else {
        Get-DefaultContextProvidersConfig
    }

$cliMcpConfig = Read-McpConfig -Path $cliMcpPath
$vscodeMcpConfig = Read-VSCodeMcpConfig -Path $vscodeMcpPath
$legacyProjectMcpConfig = if ($legacyProjectMcpPathExists) { Read-McpConfig -Path $legacyProjectMcpPath } else { $null }
$legacyProjectContainsServer = $null -ne $legacyProjectMcpConfig -and $legacyProjectMcpConfig['mcpServers'].Contains('code-review-graph')

if ($Status) {
    Show-CodeReviewGraphStatus -Config $contextProvidersConfig -CliMcpConfig $cliMcpConfig -VSCodeMcpConfig $vscodeMcpConfig -LegacyProjectConfigContainsServer:$legacyProjectContainsServer
    return
}

$providerKey = switch ($Provider) {
    'code-review-graph' { 'code_review_graph' }
    default { throw "Unsupported provider '$Provider'." }
}

$resolvedServer = $null
$runtimeAvailable = $false
if ($Mode -ne 'off') {
    $resolvedServer = Get-VerifiedCodeReviewGraphServer
    $runtimeAvailable = $null -ne $resolvedServer

    if ($Bootstrap -and -not $runtimeAvailable) {
        $resolvedServer = Install-CodeReviewGraphRuntime
        $runtimeAvailable = $true
    }

    if ($null -eq $resolvedServer) {
        throw "No verified code-review-graph runtime was found. Re-run with -Bootstrap to install it automatically, or set -Mode off as an emergency fallback."
    }
}

$contextProvidersConfig['providers'][$providerKey]['mode'] = $Mode
Write-HelixYamlFile -Path $configPath -Value $contextProvidersConfig

if ($Mode -eq 'off') {
    if ($cliMcpConfig['mcpServers'].Contains('code-review-graph')) {
        $null = $cliMcpConfig['mcpServers'].Remove('code-review-graph')
    }
    if ($vscodeMcpConfig['servers'].Contains('code-review-graph')) {
        $null = $vscodeMcpConfig['servers'].Remove('code-review-graph')
    }
    if ($legacyProjectContainsServer) {
        $null = $legacyProjectMcpConfig['mcpServers'].Remove('code-review-graph')
    }
} else {
    $cliMcpConfig['mcpServers']['code-review-graph'] = Convert-ToCliMcpServerConfig -Server $resolvedServer
    $vscodeMcpConfig['servers']['code-review-graph'] = Convert-ToVSCodeMcpServerConfig -Server $resolvedServer
    if ($legacyProjectContainsServer) {
        $null = $legacyProjectMcpConfig['mcpServers'].Remove('code-review-graph')
    }
}

if ($Mode -ne 'off' -or $cliMcpPathExists -or $cliMcpConfig['mcpServers'].Count -gt 0) {
    Write-McpConfig -Path $cliMcpPath -Config $cliMcpConfig
}

if ($Mode -ne 'off' -or $vscodeMcpPathExists -or $vscodeMcpConfig['servers'].Count -gt 0 -or @($vscodeMcpConfig['inputs']).Count -gt 0) {
    Write-VSCodeMcpConfig -Path $vscodeMcpPath -Config $vscodeMcpConfig
}

if ($legacyProjectMcpPathExists -and $null -ne $legacyProjectMcpConfig) {
    Write-McpConfig -Path $legacyProjectMcpPath -Config $legacyProjectMcpConfig
}

Show-CodeReviewGraphStatus -Config $contextProvidersConfig -CliMcpConfig $cliMcpConfig -VSCodeMcpConfig $vscodeMcpConfig -LegacyProjectConfigContainsServer:$false

if ($Mode -eq 'off') {
    Write-Host "Helix is in emergency off mode and will use default agent/search behavior."
    return
}

if (-not $SuppressNextSteps) {
    Write-Host "Next steps:"
    Write-Host "1. Build the graph in each repo you want to query."
    Write-Host "2. Keep mode 'mcp' for normal Helix setup; use '-Mode off' only as an emergency fallback."
}
