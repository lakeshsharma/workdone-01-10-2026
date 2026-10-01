# Commit any in-progress cell edit so IP/Username are captured before connect.
function Complete-ServerGridEdits {
    try {
        [void]$ServerGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$ServerGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    }
    catch { }
}

# ----------------------------------------------------------------------------
#  Connect / disconnect (per-row credentials)
# ----------------------------------------------------------------------------

$BtnConnect.Add_Click({
    Complete-ServerGridEdits
    $rows = @($script:Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Host) })
    if ($rows.Count -eq 0) {
        Show-ErrorMessage "Add at least one server (with an IP / host) before connecting."
        return
    }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $connAllStart = Get-Date

    foreach ($server in $rows) {
        Invoke-OneLinkConnectServer -Server $server
    }

    Invoke-GridRefresh $ServerGrid
    $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
    Update-ConnectionSummary
    Update-TargetCombos
    Update-DbTargetCombo
    Update-ServiceChecklist

    $connectedNow = @($script:Servers | Where-Object { $null -ne $_.Session }).Count
    Complete-OneLinkActivity -Name 'Connect All' -Target (($rows | ForEach-Object { $_.Host }) -join ', ') -Outcome ($(if (@($rows | Where-Object { $null -ne $_.Session }).Count -eq $rows.Count) { 'Success' } elseif (@($rows | Where-Object { $null -ne $_.Session }).Count -gt 0) { 'Partial' } else { 'Failed' })) -OperationSeconds (((Get-Date) - $connAllStart).TotalSeconds)
})

# Connect a SINGLE server row (shared by 'Connect All' and the row right-click menu).
function Invoke-OneLinkConnectServer {
    param([Parameter(Mandatory)]$server)
    if ($null -ne $server.Session) { return }   # already connected

    $connectStart = Get-Date
    try {
            if ([string]::IsNullOrWhiteSpace($server.Username)) { throw "Username is required." }
            if ($null -eq $server.SecurePassword -or $server.SecurePassword.Length -eq 0) { throw "Password is not set (click the Password cell)." }

            $server.Credential = New-OneLinkCredential -Username $server.Username -Password $server.SecurePassword

            Write-OneLinkLog "[$($server.Host):$($server.Port)] Connecting as $($server.Username)." -Level Info
            $server.Session = Connect-OneLinkSsh -ComputerName $server.Host -Port ([int]$server.Port) -Credential $server.Credential -Settings $script:Settings

            $validation = Test-OneLinkSshConnection -Session $server.Session

            # The tool replicates nmenu's logic inline and never invokes nmenu,
            # so its presence is irrelevant - just mark the session connected.
            $server.Status = "Connected"

            try {
                $server.Services = Get-OneLinkDiscoveredServices -Session $server.Session -Settings $script:Settings -Mappings $script:Mappings
                Update-OneLinkAuxServices -Server $server -Force   # discover non-OneLink units too, if marked Auxiliary
                $names = @($server.Services | ForEach-Object { $_.DisplayName })
                $server.ServicesDisplay = if ($names.Count) { "$($names.Count): " + ($names -join ', ') } else { '0 (none)' }
                Write-OneLinkLog "[$($server.Host)] Discovered $($names.Count) service(s): $(if ($names.Count) { $names -join ', ' } else { 'none' })." -Level Info
            }
            catch {
                $server.Services = New-Object System.Collections.Generic.List[object]
                $server.ServicesDisplay = '?'
                Write-OneLinkLog "[$($server.Host)] Service discovery failed: $($_.Exception.Message)" -Level Warning
            }

            try {
                $server.Os = Get-OneLinkOs -Session $server.Session
                Write-OneLinkLog "[$($server.Host)] OS detected: $(if ($server.Os) { $server.Os } else { 'unknown' })." -Level Info
            }
            catch { $server.Os = '' }

            # Most operations (package install, service control, SSL, MySQL) need
            # passwordless sudo. If the account doesn't have it, enable it ONCE
            # using the login password (the same account's password, already
            # entered): 'sudo -S' reads the password from stdin - no terminal
            # needed - and writes /etc/sudoers.d/onelink-admin-tool with NOPASSWD
            # for the user, i.e. the same drop-in a properly-built OneLink image
            # ships. After this, every operation runs without a password.
            try {
                $sudoChk = Invoke-OneLinkSshCommand -Session $server.Session -Command 'sudo -n true 2>/dev/null && echo OLK_SUDO_OK || echo OLK_SUDO_NO' -TimeoutSeconds 15
                if (([string]$sudoChk.Output) -notmatch 'OLK_SUDO_OK') {
                    $pwPlain = ConvertFrom-OneLinkSecure $server.SecurePassword
                    $pwArg = ConvertTo-OneLinkBashArg $pwPlain
                    $u = [string]$server.Username
                    $boot = "printf '%s\n' $pwArg | sudo -S -p '' bash -c `"echo '$u ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/onelink-admin-tool && chmod 440 /etc/sudoers.d/onelink-admin-tool`" 2>/dev/null; if sudo -n true 2>/dev/null; then echo OLK_SUDO_OK; else echo OLK_SUDO_NO; fi"
                    $bootRes = Invoke-OneLinkSshCommand -Session $server.Session -Command $boot -TimeoutSeconds 25
                    if (([string]$bootRes.Output) -match 'OLK_SUDO_OK') {
                        Write-OneLinkLog "[$($server.Host)] Enabled passwordless sudo for '$u' using the login password (wrote /etc/sudoers.d/onelink-admin-tool)." -Level Success
                    }
                    else {
                        $server.Status = "$($server.Status) - sudo unavailable (password rejected)"
                        Write-OneLinkLog "[$($server.Host)] WARNING: '$u' has no passwordless sudo and the login password was not accepted by sudo (or the account is not a sudoer). Package install, service control, SSL and MySQL will fail. Grant sudo/NOPASSWD on the server." -Level Warning
                    }
                }
            }
            catch { }

            try { Update-OneLinkServerHealth -Server $server } catch { }   # disk/memory health -> Resources button colour + Status

            $connectEnd = Get-Date
            Write-OneLinkLog "[$($server.Host)] Connected. $validation" -Level Success
            Write-OneLinkEfficiency -Operation 'Connect' -Target ([string]$server.Host) -Outcome 'Success' -Start $connectStart -End $connectEnd
        }
        catch {
            $connectEnd = Get-Date
            if ($null -ne $server.Session) { try { Disconnect-OneLinkSsh -Session $server.Session } catch { } }
            $server.Session = $null
            $server.Credential = $null
            $friendly = Get-OneLinkFriendlySshError $_.Exception.Message
            $server.Status = "Failed: $($friendly.Short)"
            Write-OneLinkLog ("[$($server.Host)] Connection failed: $($friendly.Short)" +
                $(if ($friendly.Hint) { ' ' + $friendly.Hint } else { '' }) +
                " (technical detail: $($_.Exception.Message))") -Level Error
            Write-OneLinkEfficiency -Operation 'Connect' -Target ([string]$server.Host) -Outcome 'Failed' -Start $connectStart -End $connectEnd
        }
}

$BtnDisconnect.Add_Click({
    $metricStart = Get-Date; $metricFailures = 0
    $metricTargets = @($script:Servers | Where-Object { $null -ne $_.Session })
    foreach ($server in $script:Servers) {
        if ($null -ne $server.Session) {
            try { Disconnect-OneLinkSsh -Session $server.Session } catch { $metricFailures++ }
        }
        $server.Session = $null
        $server.Credential = $null
        $server.Status = "Not connected"
        $server.ServicesDisplay = '-'
        Reset-OneLinkServerHealth -Server $server
    }
    Invoke-GridRefresh $ServerGrid
    Update-ConnectionSummary
    Update-ServiceChecklist
    $metricOutcome = if ($metricFailures -eq 0) { 'Success' } elseif ($metricFailures -lt $metricTargets.Count) { 'Partial' } else { 'Failed' }
    Complete-OneLinkActivity -Name 'Disconnect All' -Target (($metricTargets | ForEach-Object { $_.Host }) -join ', ') -Outcome $metricOutcome -OperationSeconds (((Get-Date) - $metricStart).TotalSeconds)
    Write-OneLinkLog "All SSH sessions disconnected." -Level Info
})

