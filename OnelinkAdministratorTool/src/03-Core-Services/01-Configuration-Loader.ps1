# ============================================================================
#  EMBEDDED MODULE: ConfigManager  (was Modules\ConfigManager.psm1)
# ============================================================================

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

# Standalone loader: prefer an external file beside the EXE, otherwise use the
# embedded default JSON that ships inside this script.
function Get-OneLinkConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExternalPath,
        [Parameter(Mandatory)][string]$DefaultJson
    )

    if (Test-Path -LiteralPath $ExternalPath -PathType Leaf) {
        try {
            return Get-Content -LiteralPath $ExternalPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "Unable to read external JSON configuration '$ExternalPath'. $($_.Exception.Message)"
        }
    }

    return $DefaultJson | ConvertFrom-Json
}

