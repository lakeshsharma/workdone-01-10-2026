# Run a service action (Restart/Stop) or status check on the ticked services.
# Each service runs only on target servers that are marked for it.
# Read a service's live state. First checks whether the unit is actually INSTALLED
# (a missing unit otherwise reports 'inactive' and looks like STOPPED); then maps
# `systemctl is-active` -> RUNNING/STOPPED/etc.
function Get-OneLinkServiceActiveState {
    param($Session, [string]$Unit)
    $cmd = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:`$PATH; " +
           "E=`$(systemctl list-unit-files '$Unit.service' --no-legend 2>/dev/null | wc -l); " +
           "A=`$(systemctl is-active '$Unit' 2>/dev/null); echo `"`$E|`$A`""
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 15
    $parts = (([string]$r.Output).Trim() -split '\|')
    $exists = $false
    if ($parts.Count -ge 1) { $exists = ([int]("0" + ($parts[0] -replace '\D', ''))) -ge 1 }
    $active = if ($parts.Count -ge 2) { $parts[1].Trim().ToLowerInvariant() } else { '' }
    if (-not $exists) { return 'NOT INSTALLED' }
    switch ($active) {
        'active'       { 'INSTALLED - RUNNING' }
        'inactive'     { 'INSTALLED - STOPPED' }
        'failed'       { 'INSTALLED - FAILED' }
        'activating'   { 'INSTALLED - STARTING' }
        'deactivating' { 'INSTALLED - STOPPING' }
        default        { if ([string]::IsNullOrWhiteSpace($active)) { 'INSTALLED - STOPPED' } else { "INSTALLED - $($active.ToUpperInvariant())" } }
    }
}

# Query installed OneLink application packages + versions on a server (used by
# the "Check Details (version)" button).
function Get-OneLinkAppDetails {
    param($Server)
    if ([string]$Server.Os -eq 'debian') {
        $cmd = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
dpkg-query -W -f='${Package} ${Version}\n' 'onelink*' 'virtualdrawings*' 2>/dev/null | sort
'@
    }
    else {
        $cmd = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' 'onelink*' 'virtualdrawings*' 2>/dev/null | sort
'@
    }
    $r = Invoke-OneLinkSshCommand -Session $Server.Session -Command $cmd -TimeoutSeconds 30
    return ([string]$r.Output).Trim()
}

function Invoke-OneLinkServiceControl {
    param(
        [Parameter(Mandatory)][ValidateSet('Restart','Stop','Status')][string]$Action
    )

    $targets = @(Get-OneLinkTargetHosts -Key 'Service')
    if ($targets.Count -eq 0) {
        Show-ErrorMessage "No connected server selected. Connect a server and pick a target."
        return
    }

    $services = @(Get-OneLinkCheckedServices)
    if ($services.Count -eq 0) {
        Show-ErrorMessage "Tick at least one service in the list."
        return
    }

    $metricStart = Get-Date; $metricOk = 0; $metricFailed = 0; $metricSeconds = 0.0
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        # ---- STATUS: read-only; report RUNNING/STOPPED/NOT INSTALLED per service --
        if ($Action -eq 'Status') {
            Write-OneLinkLog "Checking status of $($services -join ', ')." -Level Info
            $nl = [Environment]::NewLine
            $report = New-Object System.Collections.Generic.List[string]
            foreach ($server in $targets) {
                $serverServices = @(Get-OneLinkServerManagedServices $server)
                $rows = New-Object System.Collections.Generic.List[object]
                foreach ($svc in $services) {
                    if ($serverServices -notcontains $svc) { continue }
                    $start = Get-Date
                    try {
                        $state = Get-OneLinkServiceActiveState -Session $server.Session -Unit $svc
                        Write-OneLinkLog "[$($server.Host)] $svc = $state" -Level Info
                        Write-OneLinkEfficiency -Operation "Service Status ($svc)" -Target ([string]$server.Host) -Outcome 'Success' -Start $start -End (Get-Date)
                        $metricOk++; $metricSeconds += ((Get-Date) - $start).TotalSeconds
                        $rows.Add([pscustomobject]@{ Svc = $svc; State = ($state -replace '^INSTALLED - ', '') })
                    }
                    catch {
                        Write-OneLinkLog "[$($server.Host)] $svc status check failed. $($_.Exception.Message)" -Level Error
                        $metricFailed++; $metricSeconds += ((Get-Date) - $start).TotalSeconds
                        $rows.Add([pscustomobject]@{ Svc = $svc; State = "ERROR: $($_.Exception.Message)" })
                    }
                }
                if ($rows.Count -eq 0) { continue }
                $osTag = if ($server.Os) { $server.Os } else { 'unknown OS' }
                $report.Add("Server : $($server.Host)  ($osTag)")
                $w = ($rows | ForEach-Object { $_.Svc.Length } | Measure-Object -Maximum).Maximum
                foreach ($r in $rows) { $report.Add(("  {0}   {1}" -f $r.Svc.PadRight($w), $r.State)) }
                $report.Add('')
            }
            if ($report.Count -eq 0) {
                Show-WarningMessage "None of the ticked services apply to the selected target(s)."
            }
            else {
                $legend = "Legend:  RUNNING / STOPPED = installed and its state;   NOT INSTALLED = the service is not on that server." + $nl + ('=' * 62) + $nl
                Show-OneLinkReport -Title "$($script:AppName) - Service Status" -Body ($legend + $nl + (($report -join $nl)).TrimEnd())
            }
            return
        }

        # ---- RESTART / STOP ---------------------------------------------------
        $opName = "Service $Action"

        # Pre-check: tell the user which selected services are actually installed
        # on the target(s) before doing anything, and confirm.
        $preInstalled = New-Object System.Collections.Generic.List[string]
        $preMissing = New-Object System.Collections.Generic.List[string]
        foreach ($server in $targets) {
            $serverServices = @(Get-OneLinkServerManagedServices $server)
            foreach ($svc in $services) {
                if ($serverServices -contains $svc) { $preInstalled.Add("$($server.Host)/$svc") } else { $preMissing.Add("$($server.Host)/$svc") }
            }
        }
        $preMsg = "About to $($Action.ToUpper()):" + [Environment]::NewLine + [Environment]::NewLine +
            "Installed / present ($($preInstalled.Count)): " + ($(if ($preInstalled.Count) { $preInstalled -join ', ' } else { 'none' }))
        if ($preMissing.Count -gt 0) {
            $preMsg += [Environment]::NewLine + [Environment]::NewLine + "NOT installed - will be skipped ($($preMissing.Count)): " + ($preMissing -join ', ')
        }
        $preMsg += [Environment]::NewLine + [Environment]::NewLine + "Continue?"
        if ([System.Windows.MessageBox]::Show($preMsg, "Service $Action", 'YesNo', 'Question') -ne 'Yes') { return }

        Write-OneLinkLog "Starting '$opName' on $($services -join ', ')." -Level Info
        $succeeded = New-Object System.Collections.Generic.List[string]
        $failed = New-Object System.Collections.Generic.List[string]
        $skipped = New-Object System.Collections.Generic.List[string]

        foreach ($server in $targets) {
            $serverServices = @(Get-OneLinkServerManagedServices $server)
            foreach ($svc in $services) {
                $tag = "$($server.Host)/$svc"
                if ($serverServices -notcontains $svc) {
                    $skipped.Add($tag)
                    Write-OneLinkLog "[$($server.Host)] $svc : skipped (this server is not marked for it)." -Level Info
                    continue
                }
                $start = Get-Date
                try {
                    # OneLink services go through nmenu (nstart/nstop). Auxiliary
                    # (non-OneLink) units are not nmenu-managed, so use plain systemctl.
                    if (Test-OneLinkAuxService -Server $server -Unit $svc) {
                        $out = Invoke-OneLinkPlainServiceAction -Session $server.Session -Unit $svc -Action $Action
                    }
                    else {
                        $out = Invoke-NMenuServiceAction -Session $server.Session -Settings $script:Settings -SystemdName $svc -Action $Action
                    }
                    Write-OneLinkLog "[$($server.Host)] $svc $Action : $out" -Level Success
                    $succeeded.Add($tag)
                    Write-OneLinkEfficiency -Operation "$opName ($svc)" -Target ([string]$server.Host) -Outcome 'Success' -Start $start -End (Get-Date)
                    $metricOk++; $metricSeconds += ((Get-Date) - $start).TotalSeconds
                }
                catch {
                    $failed.Add("$tag : $($_.Exception.Message)")
                    Write-OneLinkLog "[$($server.Host)] $svc $Action FAILED. $($_.Exception.Message)" -Level Error
                    Write-OneLinkEfficiency -Operation "$opName ($svc)" -Target ([string]$server.Host) -Outcome 'Failed' -Start $start -End (Get-Date)
                    $metricFailed++; $metricSeconds += ((Get-Date) - $start).TotalSeconds
                }
            }
        }

        $summary = "$opName" + [Environment]::NewLine +
            "Succeeded ($($succeeded.Count)): " + ($(if ($succeeded.Count) { $succeeded -join ', ' } else { 'none' }))
        if ($skipped.Count -gt 0) { $summary += [Environment]::NewLine + "Skipped ($($skipped.Count)): " + ($skipped -join ', ') }
        if ($failed.Count -gt 0) {
            $summary += [Environment]::NewLine + "Failed ($($failed.Count)):" + [Environment]::NewLine + "  " + ($failed -join ([Environment]::NewLine + "  "))
            Show-WarningMessage $summary
        }
        else {
            Show-InfoMessage $summary
        }
    }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        $metricOutcome = if ($metricFailed -gt 0) { if ($metricOk -gt 0) { 'Partial' } else { 'Failed' } } elseif ($metricOk -gt 0) { 'Success' } else { 'Skipped' }
        Complete-OneLinkActivity -Name ("Service $Action ($($services -join ', '))") -Target (($targets | ForEach-Object { $_.Host }) -join ', ') -Outcome $metricOutcome -OperationSeconds $metricSeconds
    }
}

$BtnServiceAction.Add_Click({ Invoke-OneLinkServiceControl -Action (Get-ComboText $CmbServiceAction) })
$BtnServiceStatus.Add_Click({ Invoke-OneLinkServiceControl -Action 'Status' })

$BtnServiceDetails.Add_Click({
    $targets = @(Get-OneLinkTargetHosts -Key 'Service')
    if ($targets.Count -eq 0) { Show-ErrorMessage "No connected server selected. Connect a server and pick a target."; return }
    $metricStart = Get-Date; $metricOutcome = 'Failed'; $metricSeconds = $null
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $nl = [Environment]::NewLine
        $report = New-Object System.Collections.Generic.List[string]
        foreach ($server in $targets) {
            $det = Get-OneLinkAppDetails -Server $server
            $osTag = if ($server.Os) { $server.Os } else { 'unknown OS' }
            $report.Add("Server : $($server.Host)  ($osTag)")
            if ([string]::IsNullOrWhiteSpace($det)) {
                $report.Add("  (no OneLink packages installed)")
            }
            else {
                # Each line is "package version" - align into two columns.
                $pkgs = @($det -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
                        $parts = ($_.Trim() -split '\s+', 2)
                        [pscustomobject]@{ Name = $parts[0]; Version = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) }
                    })
                $w = ($pkgs | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
                $report.Add(("  {0}   {1}" -f 'PACKAGE'.PadRight($w), 'VERSION'))
                foreach ($p in $pkgs) { $report.Add(("  {0}   {1}" -f $p.Name.PadRight($w), $p.Version)) }
            }
            $report.Add('')
        }
        $metricOutcome = 'Success'
        $metricSeconds = ((Get-Date) - $metricStart).TotalSeconds
        Show-OneLinkReport -Title "$($script:AppName) - Installed Package Versions" -Body (($report -join $nl)).TrimEnd()
    }
    catch { Show-ErrorMessage "Could not read application details. $($_.Exception.Message)" }
    finally {
        $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
        if ($null -eq $metricSeconds) { $metricSeconds = ((Get-Date) - $metricStart).TotalSeconds }
        Complete-OneLinkActivity -Name 'Installed Package Details' -Target (($targets | ForEach-Object { $_.Host }) -join ', ') -Outcome $metricOutcome -OperationSeconds $metricSeconds
    }
})

