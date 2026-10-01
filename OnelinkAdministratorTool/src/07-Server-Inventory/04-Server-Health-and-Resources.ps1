# Re-discover the OneLink services installed on a connected server (the small
# refresh button in the 'OneLink Services' grid column).
function Update-OneLinkServerServices {
    param($Server)
    if ($null -eq $Server) { return }
    if ($null -eq $Server.Session) { Show-ErrorMessage "Connect this server first, then refresh its services."; return }
    $metricStart = Get-Date
    $metricOutcome = 'Failed'
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $Server.Services = Get-OneLinkDiscoveredServices -Session $Server.Session -Settings $script:Settings -Mappings $script:Mappings
        Update-OneLinkAuxServices -Server $Server -Force   # refresh non-OneLink units too, if marked Auxiliary
        try { Update-OneLinkServerHealth -Server $Server } catch { }   # refresh health indicator too
        $names = @($Server.Services | ForEach-Object { $_.DisplayName })
        $Server.ServicesDisplay = if ($names.Count) { "$($names.Count): " + ($names -join ', ') } else { '0 (none)' }
        Write-OneLinkLog "[$($Server.Host)] Re-checked services: $(if ($names.Count) { $names -join ', ' } else { 'none installed' })." -Level Info
        Invoke-GridRefresh $ServerGrid
        Update-ServiceChecklist
        $metricOutcome = 'Success'
    }
    catch {
        $Server.ServicesDisplay = '?'
        Invoke-GridRefresh $ServerGrid
        Write-OneLinkLog "[$($Server.Host)] Service re-check failed: $($_.Exception.Message)" -Level Warning
    }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        Complete-OneLinkActivity -Name 'Refresh Server Services' -Target ([string]$Server.Host) -Outcome $metricOutcome -OperationSeconds (((Get-Date) - $metricStart).TotalSeconds)
    }
}

# Reset a server's health indicator (on disconnect).
function Reset-OneLinkServerHealth {
    param($Server)
    if ($null -eq $Server) { return }
    $Server.Health = 'View'; $Server.HealthNote = ''
}

# Check disk + memory usage on a connected server and set its health indicator:
#   CRITICAL if any partition >=95% used OR memory >=95% used
#   CAUTION  if any partition >=85% used OR memory >=85% used
#   OK       otherwise
# Colours the Resources button and appends the state to the Status column. Never throws.
function Update-OneLinkServerHealth {
    param($Server)
    if ($null -eq $Server -or $null -eq $Server.Session) { return }
    try {
        $cmd = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
echo OLK_DF
df -Pk -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2
echo OLK_MEM
free -k 2>/dev/null | awk '/^Mem:/{print $2, $4, $7}'
'@
        $r = Invoke-OneLinkSshCommand -Session $Server.Session -Command $cmd -TimeoutSeconds 20
        $lines = ([string]$r.Output) -split "`r?`n"
        $section = ''
        $worstDiskPct = -1; $worstMount = ''
        $memPct = -1
        foreach ($ln in $lines) {
            $t = $ln.Trim()
            if ($t -eq 'OLK_DF') { $section = 'df'; continue }
            if ($t -eq 'OLK_MEM') { $section = 'mem'; continue }
            if ($t -eq '') { continue }
            if ($section -eq 'df') {
                $f = $t -split '\s+'
                if ($f.Count -ge 6 -and $f[4] -match '^(\d+)%$') {
                    $pct = [int]$Matches[1]
                    if ($pct -gt $worstDiskPct) { $worstDiskPct = $pct; $worstMount = $f[5] }
                }
            }
            elseif ($section -eq 'mem') {
                $m = $t -split '\s+'
                if ($m.Count -ge 1 -and $m[0] -match '^\d+$') {
                    $total = [double]$m[0]
                    $avail = if ($m.Count -ge 3 -and $m[2] -match '^\d+$') { [double]$m[2] } elseif ($m.Count -ge 2 -and $m[1] -match '^\d+$') { [double]$m[1] } else { 0 }
                    if ($total -gt 0) { $memPct = [int][math]::Round((($total - $avail) / $total) * 100) }
                }
            }
        }

        $state = 'OK'
        if (($worstDiskPct -ge 95) -or ($memPct -ge 95)) { $state = 'CRITICAL' }
        elseif (($worstDiskPct -ge 85) -or ($memPct -ge 85)) { $state = 'CAUTION' }
        if ($worstDiskPct -lt 0 -and $memPct -lt 0) { $state = 'View' }   # nothing parsed

        $parts = @()
        if ($worstDiskPct -ge 0) { $parts += "Disk $worstMount $worstDiskPct%" }
        if ($memPct -ge 0) { $parts += "Mem $memPct%" }
        $Server.HealthNote = ($parts -join ' - ')
        $Server.Health = $state

        # Reflect the state in the Status column (strip any prior health suffix first).
        # NOTE: the pattern MUST be parenthesised - without it, PowerShell operator
        # precedence makes -replace ignore the bullet part and the strip does nothing,
        # so every refresh appends another "Health: OK" (the OK * OK * OK bug).
        $bullet = [char]0x2022
        $base = ([string]$Server.Status -replace ("\s*" + $bullet + ".*$"), '').TrimEnd()
        if ($state -ne 'View') { $Server.Status = "$base  $bullet  Health: $state" } else { $Server.Status = $base }
        Write-OneLinkLog "[$($Server.Host)] Health: $state ($($Server.HealthNote))." -Level Info
    }
    catch {
        Write-OneLinkLog "[$($Server.Host)] Health check failed: $($_.Exception.Message)" -Level Warning
    }
}

# Show a server's resource details (disk partitions, memory, CPU) in a clean,
# professional popup. Read-only; runs only against a connected server. Kept fast
# (df / free / nproc) - no slow directory traversals. Artifact/package sizes are
# shown on the Package tab instead.
function Show-OneLinkServerResources {
    param($Server)
    if ($null -eq $Server) { return }
    if ($null -eq $Server.Session) { Show-ErrorMessage "Connect this server first, then view its resources."; return }
    $metricStart = Get-Date
    $metricOutcome = 'Failed'; $metricSeconds = $null
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        try { Update-OneLinkServerHealth -Server $Server; Invoke-GridRefresh $ServerGrid } catch { }   # refresh the health colour when opened
        $cmd = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
echo "===== Disk partitions ====="
df -hP -x tmpfs -x devtmpfs 2>/dev/null || df -hP 2>/dev/null
echo
echo "===== Memory ====="
free -h 2>/dev/null || free -m 2>/dev/null
echo
echo "===== CPU / uptime ====="
echo "  CPU cores : $(nproc 2>/dev/null)"
echo "  Uptime    :$(uptime 2>/dev/null | sed 's/^ *//')"
'@
        $r = Invoke-OneLinkSshCommand -Session $Server.Session -Command $cmd -TimeoutSeconds 60
        $body = ([string]$r.Output).Trim()
        if ([string]::IsNullOrWhiteSpace($body)) { $body = "(no output - the server did not return resource details)" }
        Write-OneLinkLog "[$($Server.Host)] Viewed server resources." -Level Info
        $metricOutcome = if ($r.ExitStatus -eq 0) { 'Success' } else { 'Failed' }
        $metricSeconds = ((Get-Date) - $metricStart).TotalSeconds
        Show-OneLinkReport -Title "Resources - $($Server.Host)" -Body $body
    }
    catch { Show-ErrorMessage "Could not read resources from $($Server.Host). $($_.Exception.Message)" }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        if ($null -eq $metricSeconds) { $metricSeconds = ((Get-Date) - $metricStart).TotalSeconds }
        Complete-OneLinkActivity -Name 'View Server Resources' -Target ([string]$Server.Host) -Outcome $metricOutcome -OperationSeconds $metricSeconds
    }
}

