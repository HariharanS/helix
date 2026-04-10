[CmdletBinding(DefaultParameterSetName = 'Set')]
param(
    [ValidateSet('code-review-graph')][string]$Provider = 'code-review-graph',
    [Parameter(ParameterSetName = 'Set', Mandatory = $true)]
    [ValidateSet('off', 'review-only', 'full')][string]$Mode,
    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,
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
                max_tool_calls_per_task = 5
                max_context_tokens_per_task = 800
            }
        }
    }
}

function Get-DefaultCodeReviewGraphServer {
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

    return [ordered]@{
        command = 'uvx'
        args = @('code-review-graph', 'serve')
    }
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
        $providerConfig['max_tool_calls_per_task'] = 5
    }
    if (-not $providerConfig.Contains('max_context_tokens_per_task')) {
        $providerConfig['max_context_tokens_per_task'] = 800
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
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        throw "Could not parse MCP config at '$Path'. Fix the JSON first."
    }

    if (-not $config.Contains('mcpServers') -or $null -eq $config['mcpServers']) {
        $config['mcpServers'] = [ordered]@{}
    }

    return $config
}

function Write-McpConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config
    )

    $json = $Config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine)
}

function Show-CodeReviewGraphStatus {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$McpConfig
    )

    $providerConfig = $Config['providers']['code_review_graph']
    $mode = [string]$providerConfig['mode']
    $detailLevel = [string]$providerConfig['detail_level']
    $maxToolCalls = [string]$providerConfig['max_tool_calls_per_task']
    $maxContextTokens = [string]$providerConfig['max_context_tokens_per_task']
    $server = $null

    if ($McpConfig['mcpServers'].Contains('code-review-graph')) {
        $server = $McpConfig['mcpServers']['code-review-graph']
    }

    Write-Host "Provider: code-review-graph"
    Write-Host "Mode: $mode"
    Write-Host "Detail level: $detailLevel"
    Write-Host "Budget: $maxToolCalls calls, $maxContextTokens tokens per task"

    if ($null -ne $server) {
        $args = if ($server.Contains('args') -and $server['args']) { [string]::Join(' ', $server['args']) } else { '' }
        Write-Host "MCP server: configured ($($server['command']) $args)".TrimEnd()
    } else {
        Write-Host "MCP server: not configured"
    }
}

$TargetRoot = Get-HelixRoot -StartPath $TargetRoot
$configPath = Join-Path $TargetRoot '.helix/context-providers.yml'
$mcpPath = Join-Path $TargetRoot '.mcp.json'

$contextProvidersConfig =
    if (Test-Path $configPath) {
        Ensure-ContextProvidersConfig -Config (Import-HelixYamlFile -Path $configPath)
    } else {
        Get-DefaultContextProvidersConfig
    }

$mcpConfig = Read-McpConfig -Path $mcpPath

if ($Status) {
    Show-CodeReviewGraphStatus -Config $contextProvidersConfig -McpConfig $mcpConfig
    return
}

$providerKey = switch ($Provider) {
    'code-review-graph' { 'code_review_graph' }
    default { throw "Unsupported provider '$Provider'." }
}

$contextProvidersConfig['providers'][$providerKey]['mode'] = $Mode
Write-HelixYamlFile -Path $configPath -Value $contextProvidersConfig

if ($Mode -eq 'off') {
    if ($mcpConfig['mcpServers'].Contains('code-review-graph')) {
        $null = $mcpConfig['mcpServers'].Remove('code-review-graph')
    }
} else {
    $mcpConfig['mcpServers']['code-review-graph'] = Get-DefaultCodeReviewGraphServer
}

Write-McpConfig -Path $mcpPath -Config $mcpConfig

$runtimeAvailable = (Get-Command uvx -ErrorAction SilentlyContinue) -or (Get-Command code-review-graph -ErrorAction SilentlyContinue)

Show-CodeReviewGraphStatus -Config $contextProvidersConfig -McpConfig $mcpConfig

if ($Mode -eq 'off') {
    Write-Host "Helix will ignore code-review-graph and fall back to manual context bundles."
    return
}

if (-not $runtimeAvailable) {
    Write-Warning "No 'uvx' or 'code-review-graph' executable was found in PATH. The MCP entry was written, but you still need one of those runtimes installed before the provider will work."
}

Write-Host "Next steps:"
Write-Host "1. Build the graph in each repo you want to query."
Write-Host "2. Keep the provider in 'review-only' mode until the signal quality is proven."
