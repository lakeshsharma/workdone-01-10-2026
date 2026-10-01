# Run a per-server action against the selected target(s). Continues on failure
# and shows a per-server summary at the end.
function Invoke-MultiServerOperation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$TargetSelection = '',
        [object[]]$TargetServers = $null,
        [Parameter(Mandatory)][scriptblock]$PerServerAction,
        [scriptblock]$AppliesTo
    )

    # Targets can be supplied directly (multi-select picker) or resolved from a
    # legacy selection string.
    if ($null -ne $TargetServers) {
        $targets = @($TargetServers)
        if ($targets.Count -eq 0) {
            Show-ErrorMessage "$Name`: no target server is selected. Pick one or more servers in 'Target server' (and Connect them). For Database actions, mark a server as 'Database master' or 'Database slave' first."
            return
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($TargetSelection)) {
            Show-ErrorMessage "$Name`: no target server is selected. For Database actions, mark a server as 'Database master' or 'Database slave' and click Connect All."
            return
        }
        $targets = @(Get-TargetServers -Selection $TargetSelection)
        if ($targets.Count -eq 0) {
            Show-ErrorMessage "$Name`: no connected server matches the selected target '$TargetSelection'. Connect a server first."
            return
        }
    }

    $targetDesc = ($targets | ForEach-Object { [string]$_.Host }) -join ', '
    Write-OneLinkLog "Starting '$Name' on $($targets.Count) server(s): $targetDesc." -Level Info
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $mopStart = Get-Date

    $succeeded = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]

    foreach ($server in $targets) {
        if ($AppliesTo -and -not (& $AppliesTo $server)) {
            $skipped.Add([string]$server.Host)
            Write-OneLinkLog "[$($server.Host)] $Name : skipped (this server does not have that service)." -Level Info
            continue
        }
        $opStart = Get-Date
        try {
            Write-OneLinkLog "[$($server.Host)] $Name : starting." -Level Info
            & $PerServerAction $server
            $opEnd = Get-Date
            Write-OneLinkLog "[$($server.Host)] $Name : completed in $([math]::Round(($opEnd-$opStart).TotalSeconds,2))s." -Level Success
            Write-OneLinkEfficiency -Operation $Name -Target ([string]$server.Host) -Outcome 'Success' -Start $opStart -End $opEnd
            $succeeded.Add([string]$server.Host)
        }
        catch {
            $opEnd = Get-Date
            Write-OneLinkLog "[$($server.Host)] $Name : FAILED after $([math]::Round(($opEnd-$opStart).TotalSeconds,2))s. $($_.Exception.Message)" -Level Error
            Write-OneLinkEfficiency -Operation $Name -Target ([string]$server.Host) -Outcome 'Failed' -Start $opStart -End $opEnd
            $failed.Add("$($server.Host): $($_.Exception.Message)")
        }
    }

    $script:Window.Cursor = [Windows.Input.Cursors]::Arrow

    # Record one activity metric for this whole operation (clicks/fields/time).
    $actOutcome = if ($failed.Count -gt 0) { if ($succeeded.Count -gt 0) { 'Partial' } else { 'Failed' } } elseif ($succeeded.Count -eq 0) { 'Skipped' } else { 'Success' }
    Complete-OneLinkActivity -Name $Name -Target $targetDesc -Outcome $actOutcome -OperationSeconds (((Get-Date) - $mopStart).TotalSeconds)

    if ($succeeded.Count -eq 0 -and $failed.Count -eq 0 -and $skipped.Count -gt 0) {
        Show-WarningMessage ("$Name" + [Environment]::NewLine +
            "Skipped on every target - none of them have that service:" + [Environment]::NewLine +
            "  " + ($skipped -join ', '))
        return
    }

    $summary = "$Name" + [Environment]::NewLine +
        "Succeeded ($($succeeded.Count)): " + ($(if ($succeeded.Count) { $succeeded -join ', ' } else { 'none' }))
    if ($skipped.Count -gt 0) {
        $summary += [Environment]::NewLine + "Skipped ($($skipped.Count)): " + ($skipped -join ', ')
    }
    if ($failed.Count -gt 0) {
        $summary += [Environment]::NewLine + "Failed ($($failed.Count)):" + [Environment]::NewLine +
            "  " + ($failed -join ([Environment]::NewLine + "  "))
        Show-WarningMessage $summary
    }
    else {
        Show-InfoMessage $summary
    }
}

