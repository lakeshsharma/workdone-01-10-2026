# ----------------------------------------------------------------------------
#  Multi-server state
# ----------------------------------------------------------------------------
#  Each entry is a PSCustomObject:
#     Host, Port, Username, Password (SecureString or $null), Session,
#     Credential, Status
# ----------------------------------------------------------------------------
$script:Servers = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$ServerGrid.ItemsSource = $script:Servers

# Package deployment plan (IP -> package per role), shown in the Package tab.
$script:PackagePlan = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$PackageGrid.ItemsSource = $script:PackagePlan

# Generic "All servers / pick one" target combos (Package, Services, SSL).
# The Database tab uses a single target restricted to Database-marked IPs
# Multi-select target pickers: each is a ToggleButton (shows the current selection)
# + a Popup with a checkbox per server. Keyed 'Service' / 'Cert' / 'Db' (Db = only
# servers marked Database master/slave). Rebuilt on connect / disconnect / role change.
$script:TargetPickers = [ordered]@{
    'Service' = @{ Button = $BtnTargetService; Panel = $PnlTargetService; DbOnly = $false }
    'Cert'    = @{ Button = $BtnTargetCert;    Panel = $PnlTargetCert;    DbOnly = $false }
    'Db'      = @{ Button = $BtnTargetDb;      Panel = $PnlTargetDb;      DbOnly = $true  }
}

$TxtRemoteDirectory.Text = [string]$script:Settings.Remote.UploadDirectory
$TxtInstallReason.Text = [string](Get-OneLinkProperty -Object $script:Settings.Packages -Name 'Reason' -Default "Installed via $($script:AppName)")
$TxtCertBackupPath.Text = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'OneLinkAdminTool\CertBackups'

# Log folder: use the user's saved choice (persisted across restarts) if set,
# otherwise the default Logs folder beside the EXE. Created if it doesn't exist.
$logDirectory = ''
$__prefs = Get-OneLinkPrefs
if ($__prefs -and $__prefs.PSObject.Properties['LogFolder'] -and -not [string]::IsNullOrWhiteSpace([string]$__prefs.LogFolder)) {
    $logDirectory = [string]$__prefs.LogFolder
}
if ([string]::IsNullOrWhiteSpace($logDirectory)) {
    $logDirectory = Join-Path $script:BaseDirectory ([string]$script:Settings.Logging.Directory)
}
$script:LogDirectory = $logDirectory
$script:LogFile = Initialize-OneLinkLogger -Directory $logDirectory -GuiCallback {
    param($line)
    $script:Window.Dispatcher.Invoke([action]{
        $TxtLog.AppendText($line + [Environment]::NewLine)
        $TxtLog.ScrollToEnd()
    })
}
$script:EfficiencyLogFile = Initialize-OneLinkEfficiencyLog -Directory $logDirectory
$script:MetricsLogFile = Initialize-OneLinkMetricsLog -Directory $logDirectory
$BtnLogFolder.ToolTip = "Log folder: $logDirectory`n(Click to change - $($script:AppName) remembers your choice next time.)"

# ---- Activity metrics wiring (clicks + distinct fields + time per activity) ----
$ActivityGrid.ItemsSource = $script:ActivityMetrics
Update-OneLinkActivitySummary

