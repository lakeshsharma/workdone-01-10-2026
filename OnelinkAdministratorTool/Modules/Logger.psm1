Set-StrictMode -Version Latest

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

Export-ModuleMember -Function Initialize-OneLinkLogger, Write-OneLinkLog, Protect-LogText, Get-OneLinkLogFile