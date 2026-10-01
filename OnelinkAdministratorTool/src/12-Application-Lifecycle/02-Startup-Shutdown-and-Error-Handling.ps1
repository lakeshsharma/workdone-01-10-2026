$script:Window.Add_Closing({
    foreach ($server in $script:Servers) {
        if ($null -ne $server.Session) {
            try { Disconnect-OneLinkSsh -Session $server.Session } catch { }
        }
    }
})

# ----------------------------------------------------------------------------
#  Initialize UI state and show the window.
# ----------------------------------------------------------------------------
Update-TargetCombos
Update-DbTargetCombo
Update-ConnectionSummary
Update-ServiceChecklist

Write-OneLinkLog "Application initialized. Embedded configuration loaded successfully." -Level Success
Confirm-OneLinkPoshSsh

# ----------------------------------------------------------------------------
#  Global safety net. Any unhandled error on the UI thread (a button click, a
#  timer tick, a dialog, etc.) is shown here and SWALLOWED so the tool NEVER
#  closes because of it. Setting $e.Handled = $true keeps the dispatcher (and
#  therefore the window) alive. Everything here is wrapped in try/catch so the
#  handler itself can never fail.
$script:Window.Dispatcher.add_UnhandledException({
    param($eventSource, $e)
    $detail = ''
    try { $detail = [string]$e.Exception.Message } catch { }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'An unexpected error occurred.' }
    try { Write-OneLinkLog ("Handled UI error (tool kept open): " + $detail) -Level Error } catch { }
    try {
        [System.Windows.MessageBox]::Show(
            ("Something went wrong, but the tool will stay open - you can continue working." + [Environment]::NewLine + [Environment]::NewLine +
             "If this keeps happening, note what you were doing and let support know, along with the detail below." + [Environment]::NewLine + [Environment]::NewLine +
             "Technical detail: " + $detail),
            $script:AppName, 'OK', 'Warning') | Out-Null
    }
    catch { }
    try { $e.Handled = $true } catch { }
})

# A secondary net for non-UI (background-thread) faults: cannot keep the app
# open, but records what happened instead of a silent disappearance.
try {
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($eventSource, $e)
        try { Write-OneLinkLog ("Background fault: " + [string]$e.ExceptionObject) -Level Error } catch { }
    })
}
catch { }

try {
    [void]$script:Window.ShowDialog()
}
catch {
    # Last-resort backstop if the window itself fails while showing.
    try {
        [System.Windows.MessageBox]::Show(
            ("The main window closed unexpectedly:" + [Environment]::NewLine + [Environment]::NewLine + [string]$_.Exception.Message),
            $script:AppName, 'OK', 'Error') | Out-Null
    }
    catch { }
}
