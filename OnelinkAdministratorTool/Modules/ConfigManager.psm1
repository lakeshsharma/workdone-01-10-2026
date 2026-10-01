Set-StrictMode -Version Latest

function Get-JsonConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file was not found: $Path"
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Unable to read JSON configuration '$Path'. $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-JsonConfiguration