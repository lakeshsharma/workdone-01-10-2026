# ============================================================================
#  EMBEDDED MODULE: OneLinkOperations  (was Modules\OneLinkOperations.psm1)
# ============================================================================

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
    return Get-OneLinkServiceStatusByName -Session $Session -SystemdName $systemdName
}

function Get-OneLinkServiceStatusByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$SystemdName
    )

    $command = "systemctl is-active '$SystemdName'; systemctl --no-pager --full status '$SystemdName' | head -n 20"
    return Invoke-OneLinkSshCommand -Session $Session -Command $command -TimeoutSeconds 30
}

# Safe read of an optional property (StrictMode would otherwise throw for a
# missing key, e.g. when an older external Settings.json is used).
function Get-OneLinkProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -ne $Object -and ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Object.$Name
    }
    return $Default
}

# Discover the systemd services present on a server and map each one back to a
# display name and (when available) its nmenu key. Discovered services that are
# not in the mapping still work for Check Status; Start/Restart needs an nmenu
# key.
function Get-OneLinkDiscoveredServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings
    )

    $pattern = [string](Get-OneLinkProperty -Object $Settings.Remote -Name 'ServiceUnitPattern' -Default 'onelink-*.service')
    if ([string]::IsNullOrWhiteSpace($pattern)) { $pattern = 'onelink-*.service' }

    # list-unit-files = installed units; cut/sed strip padding and the .service
    # suffix. No '$' tokens so the command needs no shell/PowerShell escaping.
    $cmd = "systemctl list-unit-files --no-legend --type=service '$pattern' 2>/dev/null | cut -d' ' -f1 | sed 's/\.service//' | sort -u"
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 30

    $names = @()
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        $names = $result.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }

    $serviceKeys = Get-OneLinkProperty -Object $Mappings.Services -Name 'ServiceKeys' -Default $null

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($systemdName in $names) {
        $display = $systemdName
        $match = @($Settings.Services | Where-Object { $_.SystemdName -eq $systemdName })
        if ($match.Count -eq 1) { $display = [string]$match[0].DisplayName }

        $nmenuKey = $null
        if ($null -ne $serviceKeys -and ($serviceKeys.PSObject.Properties.Name -contains $display)) {
            $nmenuKey = [string]$serviceKeys.$display
        }

        $entries.Add([PSCustomObject]@{
            SystemdName = $systemdName
            DisplayName = $display
            NMenuKey    = $nmenuKey
        })
    }

    return ,$entries
}

# Detect the remote OS family ('redhat' or 'debian') so the right package type
# (.rpm vs .deb) can be chosen. Uses nmenu's own ncheck_os, falling back to
# /etc/os-release.
function Get-OneLinkOs {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session)

    # Tag the machine from /etc/os-release (the reliable source); fall back to
    # ncheck_os only if that file is missing.
    $cmd = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH; if [ -r /etc/os-release ]; then . /etc/os-release; echo "$ID $ID_LIKE"; else ncheck_os 2>/dev/null; fi'
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 20
    $out = ([string]$result.Output).ToLowerInvariant()
    if ($out -match 'rhel|redhat|red hat|centos|rocky|fedora|almalinux|\bol\b') { return 'redhat' }
    if ($out -match 'debian|ubuntu|mint') { return 'debian' }
    return ($out.Trim())
}

