$BtnClearLog.Add_Click({
    $TxtLog.Clear()
})

$BtnOpenLog.Add_Click({
    if (Test-Path -LiteralPath $script:LogFile) {
        Start-Process notepad.exe -ArgumentList "`"$script:LogFile`""
    }
})

# Save the on-screen activity metrics to a CSV report (shared by the Metrics-tab
# button and the footer capture panel).
function Export-OneLinkActivityMetrics {
    if ($script:ActivityMetrics.Count -eq 0) { Show-InfoMessage "No activities recorded yet."; return }
    try {
        $sfd = New-Object Microsoft.Win32.SaveFileDialog
        $sfd.Filter = "CSV (*.csv)|*.csv|All files (*.*)|*.*"
        $sfd.FileName = ("OneLinkAdminTool-metrics_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        if (-not $sfd.ShowDialog()) { return }
        $rows = foreach ($m in $script:ActivityMetrics) {
            [PSCustomObject][ordered]@{
                TimeStarted = $m.Time; Activity = $m.Activity; TargetServer = $m.Target
                MouseClicks = $m.Clicks; FieldsEdited = $m.Inputs; ActiveTimeSeconds = $m.ActivitySeconds; ServerOpSeconds = $m.OperationSeconds; Outcome = $m.Outcome
            }
        }
        $rows | Export-Csv -LiteralPath $sfd.FileName -NoTypeInformation -Encoding UTF8
        Write-OneLinkLog "Activity metrics exported to $($sfd.FileName) ($($script:ActivityMetrics.Count) row(s))." -Level Success
        Show-InfoMessage "Activity metrics saved to:`n$($sfd.FileName)"
    }
    catch { Show-ErrorMessage "Export failed. $($_.Exception.Message)" }
}

$BtnExportMetrics.Add_Click({ Export-OneLinkActivityMetrics })

$BtnClearMetrics.Add_Click({
    if ($script:ActivityMetrics.Count -eq 0) { return }
    $ans = [System.Windows.MessageBox]::Show("Clear the on-screen activity list? (The CSV log file on disk is kept.)", 'Clear Metrics', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    $script:ActivityMetrics.Clear()
    Update-OneLinkActivitySummary
    Reset-OneLinkActivitySegment
})

# "Reset Tool" - a last-resort recovery button for when Foreman has sat open (idle)
# for a long time and starts misbehaving. The most likely real cause is a stale SSH
# session: the server (or an idle firewall/NAT) silently drops the TCP connection
# after enough inactivity, but the client-side Session object is still a live-looking
# .NET object, so the NEXT operation on it can hang for a very long time waiting on a
# dead socket - which is what actually reads as "the tool is stuck".
#
# This function is deliberately NOT a graceful disconnect (Disconnect-OneLinkSsh /
# Remove-SSHSession can itself hang against a dead session, which would defeat a
# button whose entire point is "this must always work"). It just forgets every
# session/job reference outright and resets on-screen state - nothing here can block,
# because nothing here talks to the network. The server list, credentials, package
# plan, and all settings are left untouched; the user reconnects with Connect All.
function Invoke-OneLinkResetToolState {
    try { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow } catch { }

    # Clear the two single-flight guards that gate backup/restore and Run SQL Script.
    # If a worker really is still running in its own runspace it keeps running and
    # its own completion tick simply becomes a no-op when it fires - it does not
    # throw, since these are plain hashtable flags, not the runspace itself.
    try { $script:BgState.Job = $null } catch { }
    try { $script:SqlRunState.Job = $null } catch { }

    # Drop every server's connection state. No network calls, no graceful close -
    # see the comment above for why.
    foreach ($server in @($script:Servers)) {
        $server.Session = $null
        $server.Credential = $null
        $server.Status = 'Not connected'
        $server.ServicesDisplay = '-'
        try { Reset-OneLinkServerHealth -Server $server } catch { }
    }
    try { Invoke-GridRefresh $ServerGrid } catch { }
    try { Update-ConnectionSummary } catch { }
    try { Update-ServiceChecklist } catch { }

    # Re-enable every button a stuck background job could have left disabled.
    foreach ($btn in @($BtnExportDb, $BtnImportDb, $BtnRunSqlScript)) {
        try { $btn.IsEnabled = $true } catch { }
    }
    foreach ($btn in @($BtnStopExport, $BtnStopImport)) {
        try { $btn.IsEnabled = $false } catch { }
    }

    Write-OneLinkLog "Tool state reset: all server connections and stuck job flags were cleared. Server list, settings, and the package plan were kept. Click Connect All to reconnect." -Level Warning
    Show-InfoMessage "Reset complete.`n`nEvery server connection was cleared and any stuck backup/restore or SQL-script guard was released. This did NOT close Foreman and did NOT touch your server list, credentials, settings, or package plan.`n`nClick Connect All to reconnect."
}

$BtnResetTool.Add_Click({ Invoke-OneLinkResetToolState })

