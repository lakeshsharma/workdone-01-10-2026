# ----------------------------------------------------------------------------
#  Operations
# ----------------------------------------------------------------------------

# Resolve the MySQL/MariaDB unit on a server: prefer the OS default (mysqld on
# RHEL, mysql on Debian) and report whether it is running / stopped / present.
function Resolve-OneLinkMysql {
    param($Server)
    $order = if ([string]$Server.Os -eq 'debian') { @('mysql','mysqld','mariadb') } else { @('mysqld','mysql','mariadb') }
    $fallback = $null
    foreach ($unit in $order) {
        $cmd = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:`$PATH; " +
               "A=`$(systemctl is-active '$unit' 2>/dev/null); " +
               "E=`$(systemctl list-unit-files '$unit.service' --no-legend 2>/dev/null | wc -l); " +
               "echo `"`$A|`$E`""
        $r = Invoke-OneLinkSshCommand -Session $Server.Session -Command $cmd -TimeoutSeconds 15
        $parts = (([string]$r.Output).Trim() -split '\|')
        $active = if ($parts.Count -ge 1) { $parts[0].Trim() } else { '' }
        $exists = if ($parts.Count -ge 2) { ([int]("0" + ($parts[1] -replace '\D',''))) -ge 1 } else { $false }
        if ($active -eq 'active') { return [pscustomobject]@{ Unit = $unit; State = 'Running'; Exists = $true } }
        if ($exists -and -not $fallback) { $fallback = [pscustomobject]@{ Unit = $unit; State = 'Stopped'; Exists = $true } }
    }
    if ($fallback) { return $fallback }
    return [pscustomobject]@{ Unit = $order[0]; State = 'Unknown'; Exists = $false }
}

function Set-OneLinkMysqlStatusBox {
    param([string]$State, [string]$Unit)
    switch ($State) {
        'Running' { $TxtMysqlStatus.Text = "Status: RUNNING ($Unit)"; $TxtMysqlStatus.Foreground = [System.Windows.Media.Brushes]::ForestGreen }
        'Stopped' { $TxtMysqlStatus.Text = "Status: STOPPED ($Unit)"; $TxtMysqlStatus.Foreground = [System.Windows.Media.Brushes]::Crimson }
        default   { $TxtMysqlStatus.Text = "Status: unknown"; $TxtMysqlStatus.Foreground = [System.Windows.Media.Brushes]::Gray }
    }
}

# Resolve ONE selected Database-target server (connected). For single-server DB
# operations (export / import / MySQL control); if several are ticked, uses the first.
function Get-OneLinkDbTargetServer {
    $srv = @(Get-OneLinkTargetHosts -Key 'Db')
    if ($srv.Count -eq 0) { Show-ErrorMessage "Select a Database target server (mark a server 'Database master' or 'Database slave', Connect it, then tick it under 'Target server')."; return $null }
    if ($srv.Count -gt 1) { Show-ErrorMessage 'Select exactly one Database target for this action. Create Database, Create User and Grant support multiple targets.'; return $null }
    return $srv[0]
}

# Detect the installed MySQL service and whether its data directory is initialized.
function Get-OneLinkMysqlSetupState {
    param($Session)
    $cmd = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
A=$(systemctl is-active mysqld 2>/dev/null)
DD=$(sudo my_print_defaults mysqld 2>/dev/null | sed -n 's/^--datadir=//p' | tail -1)
[ -z "$DD" ] && DD=/var/lib/mysql
INIT=no
if [ -f "$DD/mysql.ibd" ] || [ -f "$DD/ibdata1" ] || [ -d "$DD/mysql" ]; then INIT=yes; fi
echo "OLK_A=$A;OLK_INIT=$INIT"
'@
    $r = Invoke-OneLinkSshCommand -Session $Session -Command (ConvertTo-OneLinkDatabaseCommand $cmd) -TimeoutSeconds 20
    $t = ([string]$r.Output)
    $active = ($t -match 'OLK_A=active')
    $initialized = ($t -match 'OLK_INIT=yes') -or $active
    return [pscustomobject]@{ Active = $active; Initialized = $initialized }
}

function Invoke-OneLinkMysqlEnableRhel {
    param($Session, $Settings)
    # Use the installed service's initialization/configuration. Do not reset root
    # credentials or disable MySQL password validation as a side effect of Start.
    $cmd = @'
set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
if [ "$(id -u)" = 0 ]; then systemctl enable --now mysqld; else sudo -n systemctl enable --now mysqld; fi
systemctl is-active --quiet mysqld
'@
    Invoke-OneLinkDatabaseCommand -Session $Session -Command $cmd -TimeoutSeconds ([Math]::Max([int]$Settings.Ssh.CommandTimeoutSeconds, 300)) | Out-Null
    return 'MySQL is enabled and running. Existing authentication settings were preserved.'
}
function Invoke-OneLinkMysqlControl {
    param([Parameter(Mandatory)][ValidateSet('Restart','Stop','Status')][string]$Action)

    $server = Get-OneLinkDbTargetServer
    if ($null -eq $server) { return }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $start = Get-Date
    $outcome = 'Failed'
    try {
        $mysql = Resolve-OneLinkMysql -Server $server
        if (-not $mysql.Exists -and $Action -ne 'Status') {
            throw "No MySQL/MariaDB service found on $($server.Host) (looked for mysqld / mysql / mariadb)."
        }

        switch ($Action) {
            'Restart' {
                if ([string]$server.Os -eq 'redhat' -and $mysql.Unit -eq 'mysqld') {
                    # RHEL: a plain restart fails on a FRESH VM (mysqld is disabled and
                    # not initialised), so the first time we enable the installed MySQL service.
                    # Once MySQL is set up, a restart is just a restart.
                    $state = Get-OneLinkMysqlSetupState -Session $server.Session
                    if (-not $state.Initialized) {
                        # First-time setup: nothing exists yet, so nothing to lose - no
                        # scary prompt. Enable + start it the OneLink way.
                        Write-OneLinkLog "[$($server.Host)] MySQL not set up yet - running first-time enable (RHEL)." -Level Info
                        $out = Invoke-OneLinkMysqlEnableRhel -Session $server.Session -Settings $script:Settings
                        Write-OneLinkLog "[$($server.Host)] MySQL first-time enable (RHEL): $out" -Level Success
                    }
                    else {
                        # Already set up: MySQL HAS data now, so confirm before restarting.
                        $ans = [System.Windows.MessageBox]::Show(
                            "MySQL is already set up on $($server.Host). Restart it now?" + [Environment]::NewLine +
                            "The database will briefly stop while it restarts.",
                            'Restart MySQL', 'YesNo', 'Question')
                        if ($ans -ne 'Yes') { $outcome = 'Cancelled'; Write-OneLinkLog "[$($server.Host)] MySQL restart cancelled." -Level Info; return }
                        Invoke-OneLinkDatabaseServiceAction -Session $server.Session -Unit $mysql.Unit -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds) -Action 'Restart' | Out-Null
                        Write-OneLinkLog "[$($server.Host)] MySQL ($($mysql.Unit)) restarted." -Level Success
                    }
                }
                else {
                    Invoke-OneLinkDatabaseServiceAction -Session $server.Session -Unit $mysql.Unit -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds) -Action 'Restart' | Out-Null
                    Write-OneLinkLog "[$($server.Host)] MySQL ($($mysql.Unit)) restarted." -Level Success
                }
            }
            'Stop' {
                Invoke-OneLinkDatabaseServiceAction -Session $server.Session -Unit $mysql.Unit -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds) -Action 'Stop' | Out-Null
                Write-OneLinkLog "[$($server.Host)] MySQL ($($mysql.Unit)) stopped." -Level Success
            }
            'Status' {
                $r = Invoke-OneLinkSshCommand -Session $server.Session -Command ("systemctl status --no-pager -- " + (ConvertTo-OneLinkBashArg $mysql.Unit)) -TimeoutSeconds 30
                Write-OneLinkLog "[$($server.Host)] MySQL ($($mysql.Unit)) status:`n$($r.Output)" -Level Info
            }
        }

        # Re-read and show current state.
        $after = Resolve-OneLinkMysql -Server $server
        Set-OneLinkMysqlStatusBox -State $after.State -Unit $after.Unit
        $outcome = 'Success'
        Write-OneLinkEfficiency -Operation "MySQL $Action" -Target ([string]$server.Host) -Outcome 'Success' -Start $start -End (Get-Date)
    }
    catch {
        Write-OneLinkLog "[$($server.Host)] MySQL $Action failed. $($_.Exception.Message)" -Level Error
        Write-OneLinkEfficiency -Operation "MySQL $Action" -Target ([string]$server.Host) -Outcome 'Failed' -Start $start -End (Get-Date)
        Show-ErrorMessage "MySQL $Action failed on $($server.Host). $($_.Exception.Message)"
    }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        Complete-OneLinkActivity -Name "MySQL $Action" -Target ([string]$server.Host) -Outcome $outcome -OperationSeconds (((Get-Date) - $start).TotalSeconds)
    }
}

$BtnMysqlRestart.Add_Click({ Invoke-OneLinkMysqlControl -Action 'Restart' })
$BtnMysqlStop.Add_Click({ Invoke-OneLinkMysqlControl -Action 'Stop' })
$BtnMysqlStatus.Add_Click({ Invoke-OneLinkMysqlControl -Action 'Status' })

# Run a MySQL query on a target over SSH (via sudo mysql) and return the rows
# as a string array. Uses -N -B for clean, tab-separated, header-less output.
function Invoke-OneLinkMysqlQuery {
    param($Session, [string]$Sql, [int]$TimeoutSeconds = 30)
    $out = (Invoke-OneLinkDatabaseCommand -Session $Session -Command (New-OneLinkMysqlSqlCommand $Sql) -TimeoutSeconds $TimeoutSeconds).Trim()
    if ([string]::IsNullOrWhiteSpace($out)) { return @() }
    return @($out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

