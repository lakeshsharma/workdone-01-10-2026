Set-StrictMode -Version Latest

function Get-OneLinkServiceSystemdName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $match = @($Settings.Services | Where-Object { $_.DisplayName -eq $DisplayName })
    if ($match.Count -ne 1) {
        throw "Unable to determine systemd service for '$DisplayName'."
    }
    return [string]$match[0].SystemdName
}

function Get-OneLinkServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $systemdName = Get-OneLinkServiceSystemdName -Settings $Settings -DisplayName $DisplayName
    $command = "systemctl is-active '$systemdName'; systemctl --no-pager --full status '$systemdName' | head -n 20"
    return Invoke-OneLinkSshCommand -Session $Session -Command $command -TimeoutSeconds 30
}

function Test-OneLinkNMenuAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings
    )

    $cmd = "command -v '$([string]$Settings.Remote.NMenuCommand)'"
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 20
    if ($result.ExitStatus -ne 0) {
        throw "nmenu is not available for the connected account."
    }
    return $result.Output
}

Export-ModuleMember -Function Get-OneLinkServiceSystemdName, Get-OneLinkServiceStatus, Test-OneLinkNMenuAvailability