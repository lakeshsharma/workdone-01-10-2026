# ============================================================================
#  InnoDB Buffer Pool Size (Database tab).
#  Mirrors the nmenu 'ndb_innodb_buffer_pool' script's logic directly (same
#  as the rest of this tool, no nmenu dependency on the target): 75% of Total
#  RAM is the recommended/enforced maximum, the value is rounded to the
#  nearest 128 MB (MySQL's allocation granularity), and the setting lives in
#  the SAME config file on both RHEL and Debian - only the systemd unit used
#  to restart MySQL differs by OS (resolved the same way as the existing
#  Restart/Stop buttons via Resolve-OneLinkMysql).
# ============================================================================

$script:InnodbConfigFile = '/etc/mysql/mysql.conf.d/zz-aristocrat.cnf'
$script:InnodbMaxBytes = $null   # cached 75%-of-RAM cap from the last Check/Apply on the current target

# Bytes -> "X.XX GB" / "X.XX MB" (matches the nmenu script's bytes_to_human()).
function Format-OneLinkInnodbSize {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    return ('{0:N2} MB' -f ($Bytes / 1MB))
}

# Parse a user-entered size like "1.5G", "500M", "2GB", "1.5g", "500mb" into
# bytes. Matches the nmenu script's ^[0-9]+(\.[0-9]+)?[GgMm]$ validation,
# extended to also accept an optional trailing "B" (GB/Gb/gb/MB/Mb/mb).
function Convert-OneLinkInnodbSizeToBytes {
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t -notmatch '^(?<num>[0-9]+(\.[0-9]+)?)\s*(?<unit>[GgMm][Bb]?)$') {
        throw "Invalid format. Please provide a number followed by G or M (e.g., 1.5G, 500M, 2GB)."
    }
    $value = [double]$Matches['num']
    $unit = $Matches['unit'].Substring(0,1).ToUpperInvariant()
    if ($unit -eq 'G') { return [math]::Round($value * 1GB) }
    return [math]::Round($value * 1MB)
}

# Round to the nearest 128 MB multiple, exactly like the nmenu script's
# NEAREST=$(( (BYTES + MULTIPLE/2) / MULTIPLE * MULTIPLE )) integer math.
function Get-OneLinkInnodbNearest128 {
    param([double]$Bytes)
    $chunk = 128MB
    return [math]::Floor(($Bytes + ($chunk / 2)) / $chunk) * $chunk
}

# Read current innodb_buffer_pool_size + /proc/meminfo from the target and
# compute the recommended maximum: 75% of Total RAM, minus a 0.001 GB
# rounding-safety margin - identical math to the nmenu script.
function Get-OneLinkInnodbStatus {
    param($Session)
    $rows = @(Invoke-OneLinkMysqlQuery -Session $Session -Sql "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';")
    $current = 0.0
    if ($rows.Count -gt 0) {
        $parts = $rows[0] -split "`t"
        if ($parts.Count -ge 2) { $current = [double]("0" + ($parts[1] -replace '[^\d.]','')) }
    }

    $memCmd = 'T=$(awk ''/^MemTotal:/{print $2}'' /proc/meminfo); A=$(awk ''/^MemAvailable:/{print $2}'' /proc/meminfo); echo "$T|$A"'
    $mem = Invoke-OneLinkSshCommand -Session $Session -Command $memCmd -TimeoutSeconds 15
    $memParts = ([string]$mem.Output).Trim() -split '\|'
    $totalKb = if ($memParts.Count -ge 1) { [double]("0" + ($memParts[0] -replace '\D','')) } else { 0 }
    $availKb = if ($memParts.Count -ge 2) { [double]("0" + ($memParts[1] -replace '\D','')) } else { 0 }

    $totalBytes = $totalKb * 1KB
    $availBytes = $availKb * 1KB
    $maxGbSafe = [math]::Round(($totalBytes * 0.75 / 1GB) - 0.001, 3)
    if ($maxGbSafe -lt 0) { $maxGbSafe = 0 }
    $maxBytesSafe = [math]::Round($maxGbSafe * 1GB)

    [pscustomobject]@{
        CurrentBytes = $current
        TotalBytes   = $totalBytes
        AvailBytes   = $availBytes
        MaxBytesSafe = $maxBytesSafe
    }
}

# Refresh the info box + live-validate whatever is currently typed.
function Update-OneLinkInnodbWarning {
    $text = $TxtInnodbSize.Text
    if ([string]::IsNullOrWhiteSpace($text)) {
        $BrdInnodbWarn.Background = [System.Windows.Media.Brushes]::Transparent
        $TxtInnodbWarn.Foreground = $script:Window.FindResource('MutedTextBrush')
        $TxtInnodbWarn.Text = "Enter a size (e.g. 1.5G, 500M) and click 'Check Current / Recommended' to compare it against this server's RAM."
        return
    }
    try {
        $bytes = Convert-OneLinkInnodbSizeToBytes $text
    }
    catch {
        $BrdInnodbWarn.Background = [System.Windows.Media.Brushes]::Transparent
        $TxtInnodbWarn.Foreground = $script:Window.FindResource('WarningBrush')
        $TxtInnodbWarn.Text = $_.Exception.Message
        return
    }
    if ($null -eq $script:InnodbMaxBytes) {
        $BrdInnodbWarn.Background = [System.Windows.Media.Brushes]::Transparent
        $TxtInnodbWarn.Foreground = $script:Window.FindResource('MutedTextBrush')
        $TxtInnodbWarn.Text = "$(Format-OneLinkInnodbSize $bytes) entered. Click 'Check Current / Recommended' first to compare it against this server's RAM."
        return
    }
    if ($bytes -gt $script:InnodbMaxBytes) {
        $BrdInnodbWarn.Background = [System.Windows.Media.Brushes]::MistyRose
        $TxtInnodbWarn.Foreground = $script:Window.FindResource('DangerBrush')
        $TxtInnodbWarn.Text = "CAUTION: $(Format-OneLinkInnodbSize $bytes) exceeds the recommended maximum ($(Format-OneLinkInnodbSize $script:InnodbMaxBytes) = 75% of Total RAM). Please enter the recommended size or less."
    }
    else {
        $BrdInnodbWarn.Background = [System.Windows.Media.Brushes]::Honeydew
        $TxtInnodbWarn.Foreground = $script:Window.FindResource('SuccessBrush')
        $TxtInnodbWarn.Text = "OK: $(Format-OneLinkInnodbSize $bytes) is within the recommended maximum ($(Format-OneLinkInnodbSize $script:InnodbMaxBytes))."
    }
}
$TxtInnodbSize.Add_TextChanged({ Update-OneLinkInnodbWarning })

function Invoke-OneLinkInnodbCheck {
    $server = Get-OneLinkDbTargetServer
    if ($null -eq $server) { return }
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $info = Get-OneLinkInnodbStatus -Session $server.Session
        $script:InnodbMaxBytes = $info.MaxBytesSafe
        $TxtInnodbInfo.Text =
            "Current innodb_buffer_pool_size: $(Format-OneLinkInnodbSize $info.CurrentBytes)" + [Environment]::NewLine +
            "Total RAM: $(Format-OneLinkInnodbSize $info.TotalBytes)   |   Available RAM: $(Format-OneLinkInnodbSize $info.AvailBytes)" + [Environment]::NewLine +
            "Recommended maximum (75% of Total RAM): $(Format-OneLinkInnodbSize $info.MaxBytesSafe)"
        Update-OneLinkInnodbWarning
        Write-OneLinkLog "[$($server.Host)] InnoDB buffer pool checked: current $(Format-OneLinkInnodbSize $info.CurrentBytes), recommended max $(Format-OneLinkInnodbSize $info.MaxBytesSafe)." -Level Info
    }
    catch {
        Show-ErrorMessage "Could not read InnoDB buffer pool / RAM info from $($server.Host). $($_.Exception.Message)"
    }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
    }
}

function Invoke-OneLinkInnodbApply {
    $server = Get-OneLinkDbTargetServer
    if ($null -eq $server) { return }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $start = Get-Date
    $outcome = 'Failed'
    try {
        $bytes = Convert-OneLinkInnodbSizeToBytes $TxtInnodbSize.Text

        $info = Get-OneLinkInnodbStatus -Session $server.Session
        $script:InnodbMaxBytes = $info.MaxBytesSafe
        Update-OneLinkInnodbWarning

        if ($bytes -gt $info.MaxBytesSafe) {
            $outcome = 'Cancelled'
            Show-ErrorMessage ("Entered value ({0}) exceeds 75% of total system RAM (recommended maximum: {1} on {2}). Please enter a size within the recommended limit." -f (Format-OneLinkInnodbSize $bytes), (Format-OneLinkInnodbSize $info.MaxBytesSafe), $server.Host)
            return
        }

        $nearest = Get-OneLinkInnodbNearest128 $bytes
        $note = if ($nearest -ne $bytes) { "MySQL enforces innodb_buffer_pool_size in multiples of 128 MB - the nearest multiple to $(Format-OneLinkInnodbSize $bytes) is $(Format-OneLinkInnodbSize $nearest)." + [Environment]::NewLine } else { '' }

        $ans = [System.Windows.MessageBox]::Show(
            $note + "This will set innodb_buffer_pool_size to $(Format-OneLinkInnodbSize $nearest) on $($server.Host) and restart MySQL. Proceed?",
            'InnoDB Buffer Pool Size', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $outcome = 'Cancelled'; Write-OneLinkLog "[$($server.Host)] InnoDB buffer pool change cancelled." -Level Info; return }

        $cfgArg = ConvertTo-OneLinkBashArg $script:InnodbConfigFile
        $bytesArg = ConvertTo-OneLinkBashArg ([string][int64]$nearest)
        $tmpl = @'
set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
CFG=__CFGQ__
BYTES=__BYTESQ__
if [ ! -f "$CFG" ]; then echo "Config file $CFG not found on this server." >&2; exit 1; fi
BACKUP="${CFG}.bak.$(date +%F_%H%M%S)"
sudo cp "$CFG" "$BACKUP"
if grep -q "innodb_buffer_pool_size" "$CFG"; then
    sudo sed -i "s/^\s*innodb_buffer_pool_size\s*=.*/innodb_buffer_pool_size=$BYTES/" "$CFG"
else
    sudo sed -i "/^\[mysqld\]/a innodb_buffer_pool_size=$BYTES" "$CFG"
fi
echo "BACKUP=$BACKUP"
'@
        $cmd = $tmpl.Replace('__CFGQ__', $cfgArg).Replace('__BYTESQ__', $bytesArg)
        $cfgOut = Invoke-OneLinkDatabaseCommand -Session $server.Session -Command $cmd -TimeoutSeconds 60
        $backupPath = $null
        if ($cfgOut -match 'BACKUP=(\S+)') { $backupPath = $Matches[1] }
        Write-OneLinkLog "[$($server.Host)] $script:InnodbConfigFile updated (innodb_buffer_pool_size=$([int64]$nearest)). Backup: $backupPath" -Level Info

        $mysql = Resolve-OneLinkMysql -Server $server
        try {
            Invoke-OneLinkDatabaseServiceAction -Session $server.Session -Unit $mysql.Unit -Action 'Restart' -TimeoutSeconds ([Math]::Max([int]$script:Settings.Ssh.CommandTimeoutSeconds, 120))
        }
        catch {
            # Mirror the nmenu script's rollback: if MySQL fails to come back up
            # with the new setting, restore the previous config and retry the start.
            if ($backupPath) {
                $restoreTmpl = @'
set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
sudo cp __BACKUPQ__ __CFGQ__
if [ "$(id -u)" = 0 ]; then systemctl start __UNITQ__; else sudo -n systemctl start __UNITQ__; fi
'@
                $restoreCmd = $restoreTmpl.Replace('__BACKUPQ__', (ConvertTo-OneLinkBashArg $backupPath)).Replace('__CFGQ__', $cfgArg).Replace('__UNITQ__', (ConvertTo-OneLinkBashArg $mysql.Unit))
                try { Invoke-OneLinkDatabaseCommand -Session $server.Session -Command $restoreCmd -TimeoutSeconds 60 | Out-Null } catch { }
            }
            throw "MySQL failed to restart with the new innodb_buffer_pool_size. The previous configuration was restored from $backupPath. $($_.Exception.Message)"
        }

        $after = Get-OneLinkInnodbStatus -Session $server.Session
        $script:InnodbMaxBytes = $after.MaxBytesSafe
        $TxtInnodbInfo.Text =
            "Current innodb_buffer_pool_size: $(Format-OneLinkInnodbSize $after.CurrentBytes)" + [Environment]::NewLine +
            "Total RAM: $(Format-OneLinkInnodbSize $after.TotalBytes)   |   Available RAM: $(Format-OneLinkInnodbSize $after.AvailBytes)" + [Environment]::NewLine +
            "Recommended maximum (75% of Total RAM): $(Format-OneLinkInnodbSize $after.MaxBytesSafe)"
        Update-OneLinkInnodbWarning
        Set-OneLinkMysqlStatusBox -State 'Running' -Unit $mysql.Unit

        $outcome = 'Success'
        Write-OneLinkLog "[$($server.Host)] innodb_buffer_pool_size set to $(Format-OneLinkInnodbSize $after.CurrentBytes) and MySQL restarted." -Level Success
        Write-OneLinkEfficiency -Operation 'InnoDB Buffer Pool' -Target ([string]$server.Host) -Outcome 'Success' -Start $start -End (Get-Date)
    }
    catch {
        Write-OneLinkEfficiency -Operation 'InnoDB Buffer Pool' -Target ([string]$server.Host) -Outcome 'Failed' -Start $start -End (Get-Date)
        Show-ErrorMessage "InnoDB buffer pool change failed on $($server.Host). $($_.Exception.Message)"
    }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        Complete-OneLinkActivity -Name 'InnoDB Buffer Pool' -Target ([string]$server.Host) -Outcome $outcome -OperationSeconds (((Get-Date) - $start).TotalSeconds)
    }
}

$BtnInnodbCheck.Add_Click({ Invoke-OneLinkInnodbCheck })
$BtnInnodbApply.Add_Click({ Invoke-OneLinkInnodbApply })

