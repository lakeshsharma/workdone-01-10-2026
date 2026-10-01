# ============================================================================
#  EMBEDDED MODULE: Logger  (was Modules\Logger.psm1)
# ============================================================================

$script:LogFile = $null
$script:LogCallback = $null

function Initialize-OneLinkLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [scriptblock]$GuiCallback
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    $script:LogFile = Join-Path $Directory ("OneLinkAdminTool_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $script:LogCallback = $GuiCallback
    New-Item -Path $script:LogFile -ItemType File -Force | Out-Null
    return $script:LogFile
}

# ----------------------------------------------------------------------------
#  Persisted user preferences (survive EXE restarts). Stored as a small JSON
#  file in the per-user app folder (%LOCALAPPDATA%\OneLinkAdminTool) - no extra
#  dependency, keeps the tool a standalone EXE. Currently remembers the chosen
#  log folder.
# ----------------------------------------------------------------------------
function Get-OneLinkPrefsPath {
    return (Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\preferences.json')
}

function Get-OneLinkPrefs {
    $p = Get-OneLinkPrefsPath
    if (Test-Path -LiteralPath $p) {
        try { return (Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { }
    }
    return $null
}

function Save-OneLinkPref {
    param([Parameter(Mandatory)][string]$Name, [string]$Value)
    try {
        $p = Get-OneLinkPrefsPath
        $dir = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = Get-OneLinkPrefs
        if ($null -eq $obj) { $obj = [pscustomobject]@{} }
        $obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        $obj | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        return $true
    }
    catch { return $false }
}

function Protect-LogText {
    [CmdletBinding()]
    param([AllowNull()][string]$Message)

    if ($null -eq $Message) { return "" }

    $protected = $Message
    $protected = $protected -replace '(?i)(password\s*[:=]\s*)\S+', '$1********'
    $protected = $protected -replace '(?i)(passwd\s*[:=]\s*)\S+', '$1********'
    return $protected
}

function Write-OneLinkLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Debug','Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )

    $safeMessage = Protect-LogText -Message $Message
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $safeMessage

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }

    if ($script:LogCallback) {
        & $script:LogCallback $line
    }
}

function Get-OneLinkLogFile {
    return $script:LogFile
}

