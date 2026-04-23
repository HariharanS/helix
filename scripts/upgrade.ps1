[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$PassthroughArgs
)

& (Join-Path $PSScriptRoot 'sync-helix.ps1') @PassthroughArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
