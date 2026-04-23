[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$PassthroughArgs
)

& (Join-Path $PSScriptRoot 'init-meta-repo.ps1') @PassthroughArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
