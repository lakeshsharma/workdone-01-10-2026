# ============================================================================
#  Run SQL Script (Database tab) - mirrors nmenu's ndb_run <file>: run an
#  existing .sql file (already on the target server) through the MySQL root
#  socket. Adds a search-by-name step across the whole server (nmenu's own
#  file picker only browsed $HOME) and a dedicated progress popup.
# ============================================================================

$script:SqlRunState = @{ Job = $null }   # single-flight guard; a hashtable so a
                                          # GetNewClosure timer tick can safely
                                          # clear it (see the Watch-OneLinkBgJob
                                          # GOTCHA comment above for why a plain
                                          # $script:var would NOT work here).

# Search the ENTIRE target server for .sql files whose name contains $Term
# (case-insensitive), skipping virtual filesystems for speed/safety.
function Invoke-OneLinkSqlScriptSearch {
    $server = Get-OneLinkDbTargetServer
    if ($null -eq $server) { return }
    $term = $TxtSqlSearchTerm.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($term)) { Show-ErrorMessage "Type part of the script name to search for (e.g. 'test')."; return }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $CmbSqlScriptFound.Items.Clear()
    $TxtSqlSearchStatus.Text = "Searching $($server.Host) for '*$term*.sql' - this can take a moment on a large disk..."
    $TxtSqlSearchStatus.Foreground = $script:Window.FindResource('MutedTextBrush')
    try {
        $termArg = ConvertTo-OneLinkBashArg $term
        $tmpl = @'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
T=__TERMQ__
PATTERN="*$T*.sql"
run_find() { if [ "$(id -u)" = 0 ]; then find "$@"; else sudo -n find "$@" 2>/dev/null || find "$@"; fi; }
run_find / \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap \) -prune -o -type f -iname "$PATTERN" -print 2>/dev/null | sort -u | head -n 200
'@
        $cmd = $tmpl.Replace('__TERMQ__', $termArg)
        $out = Invoke-OneLinkDatabaseCommand -Session $server.Session -Command $cmd -TimeoutSeconds 150
        $paths = @($out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        foreach ($p in $paths) { [void]$CmbSqlScriptFound.Items.Add($p) }
        if ($paths.Count -eq 0) {
            $TxtSqlSearchStatus.Text = "No .sql files matching '$term' were found on $($server.Host)."
            $TxtSqlSearchStatus.Foreground = $script:Window.FindResource('WarningBrush')
        }
        else {
            $CmbSqlScriptFound.SelectedIndex = 0
            $TxtSqlSearchStatus.Text = "Found $($paths.Count) script(s) matching '$term' on $($server.Host)."
            $TxtSqlSearchStatus.Foreground = $script:Window.FindResource('SuccessBrush')
        }
        Write-OneLinkLog "[$($server.Host)] SQL script search for '$term': $($paths.Count) match(es)." -Level Info
    }
    catch {
        $TxtSqlSearchStatus.Text = "Search failed: $($_.Exception.Message)"
        $TxtSqlSearchStatus.Foreground = $script:Window.FindResource('DangerBrush')
        Show-ErrorMessage "Could not search for SQL scripts on $($server.Host). $($_.Exception.Message)"
    }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
}
$BtnSqlSearch.Add_Click({ Invoke-OneLinkSqlScriptSearch })

# Translate a raw MySQL/SSH failure into a short, human-readable explanation.
# The full raw output is always shown too, underneath this summary line.
function Get-OneLinkSqlErrorHint {
    param([string]$RawOutput, [string]$ExceptionMessage)
    $text = if (-not [string]::IsNullOrWhiteSpace($RawOutput)) { $RawOutput } else { $ExceptionMessage }
    if ([string]::IsNullOrWhiteSpace($text)) { return 'The script failed for an unknown reason (no output was returned).' }

    switch -Regex ($text) {
        'ERROR 1045'                                    { return "Access denied - the database rejected the connection (the MySQL root socket login is not working)." }
        'ERROR 1049'                                     { return "Unknown database - the script references a database that does not exist on this server. Check any USE/database name in the script." }
        'ERROR 1050'                                     { return "Table already exists - the script tried to CREATE a table that is already there." }
        'ERROR 1051|ERROR 1146'                          { return "Unknown table - the script references a table that does not exist. Check the table name and that the right database is selected." }
        'ERROR 1054'                                     { return "Unknown column - the script references a column that does not exist in the table." }
        'ERROR 1062'                                     { return "Duplicate entry - the script tried to insert a row that violates a UNIQUE/PRIMARY KEY constraint." }
        'ERROR 1064'                                      { return "SQL syntax error - there is a mistake in the script's SQL near the point MySQL reported. Check the exact line in the script." }
        'ERROR 1136'                                     { return "Column count mismatch - an INSERT statement supplies a different number of values than the table has columns." }
        'ERROR 1142|ERROR 1044|Access denied for user'   { return "Permission denied - the database account does not have the privilege needed for this statement." }
        'ERROR 1215|ERROR 1452'                          { return "Foreign key constraint failed - the script's data violates a foreign key relationship (e.g. inserting a child row before its parent)." }
        'ERROR 2002|Can''t connect'                      { return "Could not connect to MySQL - the database service may be stopped. Check MySQL status (Restart/Status buttons above) and try again." }
        'not found on the server'                        { return "The selected .sql file no longer exists on the server (it may have been moved or deleted after the search)." }
        'MySQL/MariaDB client is not installed'          { return "No MySQL/MariaDB client is installed on this server, so the script could not be run." }
        'a password is required|sudo:.*password'         { return "Passwordless sudo is not available for this account, so the command could not run as root. Reconnect the server (the tool tries to configure this automatically) or grant sudo." }
        default                                           { return "The script did not complete successfully. See the full output below for MySQL's exact error." }
    }
}

# Self-contained worker: run one .sql file already on the target server.
$script:SqlRunWorker = {
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($DatabaseFunctions))
    # Pre-set these BEFORE anything that could throw, so the watcher (which reads
    # them under this app's Set-StrictMode -Version Latest) never hits a missing
    # hashtable key - see the InnoDB Get-OneLinkInnodbStatus fix for the same class of bug.
    $sync.RawOutput = ''
    $sync.ExitStatus = $null
    $sess = $null
    try {
        if (($env:PSModulePath -split ';') -notcontains $ModulesRoot) { $env:PSModulePath = $ModulesRoot + ';' + $env:PSModulePath }
        Import-Module Posh-SSH -ErrorAction Stop
        $sec = ConvertTo-SecureString $SrvPass -AsPlainText -Force
        $cred = [pscredential]::new($SrvUser, $sec)
        $sync.Status = "Connecting to $SrvHost ..."
        $sess = New-SSHSession -ComputerName $SrvHost -Port $SrvPort -Credential $cred -AcceptKey -ErrorAction Stop

        $sync.Status = "Running $FilePath on $SrvHost (large scripts can take a while) ..."
        $wrapped = ConvertTo-OneLinkDatabaseCommand (New-OneLinkSqlScriptRunCommand -FilePath $FilePath)
        $r = Invoke-SSHCommand -SSHSession $sess -Command $wrapped -TimeOut $Timeout
        $sync.RawOutput = ((@($r.Output) + @($r.Error)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        $sync.ExitStatus = $r.ExitStatus
        $sync.Ok = ($r.ExitStatus -eq 0)
        $sync.Message = if ($sync.Ok) { 'Script completed successfully.' } else { "Script exited with code $($r.ExitStatus)." }
    }
    catch {
        $sync.Ok = $false
        $sync.Message = $_.Exception.Message
    }
    finally {
        try { if ($sess) { Remove-SSHSession -SSHSession $sess -ErrorAction SilentlyContinue | Out-Null } } catch { }
        $sync.Done = $true
    }
}

# Build the non-modal "Run SQL Script" progress popup. Closing (X / Alt+F4) is
# blocked while the script is still running, same spirit as the other
# irreversible-operation confirms in this tool.
function Show-OneLinkSqlRunWindow {
    param([string]$ScriptPath, [string]$HostName)
    $win = New-Object System.Windows.Window
    $win.Title = 'Run SQL Script'
    $win.Width = 760; $win.Height = 520
    $win.MinWidth = 480; $win.MinHeight = 320
    $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5F7FB'))
    if ($script:Window) { $win.Owner = $script:Window }

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($h in @('Auto', 'Auto', '*', 'Auto')) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = [System.Windows.GridLength]::new(1, $(if ($h -eq '*') { 'Star' } else { 'Auto' }))
        [void]$grid.RowDefinitions.Add($rd)
    }

    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = New-OneLinkHeaderBrush
    $hdr.Padding = '16,11'
    $htxt = New-Object System.Windows.Controls.TextBlock
    $htxt.Text = 'Run SQL Script'; $htxt.Foreground = [System.Windows.Media.Brushes]::White; $htxt.FontSize = 15; $htxt.FontWeight = 'Bold'
    $hdr.Child = $htxt
    [System.Windows.Controls.Grid]::SetRow($hdr, 0); [void]$grid.Children.Add($hdr)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = "$ScriptPath  ->  $HostName"
    $sub.Margin = '14,10,14,0'; $sub.FontSize = 12; $sub.Foreground = [System.Windows.Media.Brushes]::Gray; $sub.TextWrapping = 'Wrap'
    [System.Windows.Controls.Grid]::SetRow($sub, 1); [void]$grid.Children.Add($sub)

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.Brushes]::White
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E2E8F0'))
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Margin = '14,10,14,6'
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = 'Waiting for the script to start...'
    $tb.IsReadOnly = $true; $tb.AcceptsReturn = $true
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Courier New, monospace')
    $tb.FontSize = 13; $tb.TextWrapping = 'NoWrap'
    $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'
    $tb.BorderThickness = New-Object System.Windows.Thickness(0)
    $tb.Padding = '14,12'; $tb.Background = [System.Windows.Media.Brushes]::White
    $card.Child = $tb
    [System.Windows.Controls.Grid]::SetRow($card, 2); [void]$grid.Children.Add($card)

    $footer = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = '*'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'
    [void]$footer.ColumnDefinitions.Add($c0); [void]$footer.ColumnDefinitions.Add($c1)
    $footer.Margin = '14,0,14,12'

    $status = New-Object System.Windows.Controls.TextBlock
    $status.Text = 'Status: Starting...'; $status.FontWeight = 'Bold'; $status.VerticalAlignment = 'Center'
    $status.Foreground = Get-OneLinkStyle 'WarningBrush'
    [System.Windows.Controls.Grid]::SetColumn($status, 0); [void]$footer.Children.Add($status)

    $close = New-Object System.Windows.Controls.Button
    $close.Content = 'Close'; $close.Width = 100; $close.Height = 30; $close.IsEnabled = $false
    $primaryStyle = Get-OneLinkStyle 'PrimaryButtonStyle'
    if ($primaryStyle) { $close.Style = $primaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($close, 1); [void]$footer.Children.Add($close)
    [System.Windows.Controls.Grid]::SetRow($footer, 3); [void]$grid.Children.Add($footer)

    $win.Content = $grid

    $running = @{ Value = $true }
    $win.Add_Closing({
        param($closingSender, $closingArgs)
        if ($running.Value) {
            $closingArgs.Cancel = $true
            [System.Windows.MessageBox]::Show('The script is still running. Please wait for it to finish.', 'Run SQL Script', 'OK', 'Information') | Out-Null
        }
    }.GetNewClosure())
    $close.Add_Click({ $running.Value = $false; $win.Close() }.GetNewClosure())

    $win.Show()
    return [pscustomobject]@{ Window = $win; Output = $tb; Status = $status; Close = $close; Running = $running }
}

# Poll the SQL-run background job on the UI thread; update the popup, and
# report a human-friendly result when it finishes.
function Watch-OneLinkSqlRunJob {
    param($Ctx, $Popup, $RunButton, [string]$TargetHost, [string]$ScriptPath)
    $state = $script:SqlRunState
    $state.Job = $Ctx
    $startTime = Get-Date
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $tick = {
        if ($Ctx.Sync.Done -or $Ctx.Handle.IsCompleted) {
            $timer.Stop()
            $state.Job = $null
            $RunButton.IsEnabled = $true
            try { $Ctx.PS.EndInvoke($Ctx.Handle) } catch { }
            try { $Ctx.PS.Dispose() } catch { }
            try { $Ctx.Runspace.Dispose() } catch { }
            if (-not $Ctx.Sync.Done) {
                $Ctx.Sync.Ok = $false
                if ([string]::IsNullOrWhiteSpace([string]$Ctx.Sync.Message)) { $Ctx.Sync.Message = 'Stopped unexpectedly.' }
            }
            $ok = [bool]$Ctx.Sync.Ok
            $raw = [string]$Ctx.Sync.RawOutput
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            if ($ok) {
                $Popup.Status.Text = 'Status: Completed successfully.'
                $Popup.Status.Foreground = Get-OneLinkStyle 'SuccessBrush'
                $Popup.Output.Text = if ([string]::IsNullOrWhiteSpace($raw)) { '(The script ran successfully and produced no output.)' } else { $raw }
                Write-OneLinkLog "[$TargetHost] SQL script '$ScriptPath' completed successfully." -Level Success
            }
            else {
                $hint = Get-OneLinkSqlErrorHint -RawOutput $raw -ExceptionMessage ([string]$Ctx.Sync.Message)
                $Popup.Status.Text = 'Status: FAILED.'
                $Popup.Status.Foreground = Get-OneLinkStyle 'DangerBrush'
                $bodyText = $hint
                if (-not [string]::IsNullOrWhiteSpace($raw)) { $bodyText += [Environment]::NewLine + [Environment]::NewLine + '--- Full output ---' + [Environment]::NewLine + $raw }
                $Popup.Output.Text = $bodyText
                Write-OneLinkLog "[$TargetHost] SQL script '$ScriptPath' failed: $hint" -Level Error
            }
            $Popup.Running.Value = $false
            $Popup.Close.IsEnabled = $true
            Write-OneLinkEfficiency -Operation 'Run SQL Script' -Target $TargetHost -Outcome ($(if ($ok) { 'Success' } else { 'Failed' })) -Start $startTime -End (Get-Date)
            Complete-OneLinkActivity -Name 'Run SQL Script' -Target $TargetHost -Outcome ($(if ($ok) { 'Success' } else { 'Failed' })) -OperationSeconds $elapsed
        }
        else {
            $Popup.Output.Text = [string]$Ctx.Sync.Status
        }
    }.GetNewClosure()
    $timer.Add_Tick($tick)
    $timer.Start()
}

function Invoke-OneLinkSqlScriptRun {
    if ($script:SqlRunState.Job) { Show-ErrorMessage "A SQL script is already running. Wait for it to finish."; return }
    $server = Get-OneLinkDbTargetServer
    if ($null -eq $server) { return }
    $path = Get-ComboText $CmbSqlScriptFound
    if ([string]::IsNullOrWhiteSpace($path)) { Show-ErrorMessage "Search for and select a .sql script to run first."; return }

    $ans = [System.Windows.MessageBox]::Show(
        "This will run the SQL script:`n$path`n`non $($server.Host), against its live database." +
        "`n`nThis can change or delete data and CANNOT be undone automatically. Proceed?",
        'Run SQL Script', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { Write-OneLinkLog "[$($server.Host)] Run SQL script cancelled ($path)." -Level Info; return }

    $popup = Show-OneLinkSqlRunWindow -ScriptPath $path -HostName ([string]$server.Host)
    $BtnRunSqlScript.IsEnabled = $false

    $vars = @{
        SrvHost = [string]$server.Host; SrvPort = [int]$server.Port
        SrvUser = $server.Credential.UserName; SrvPass = $server.Credential.GetNetworkCredential().Password
        FilePath = $path; Timeout = [Math]::Max([int]$script:Settings.Ssh.CommandTimeoutSeconds, 1800)
        DatabaseFunctions = Get-OneLinkDatabaseWorkerFunctions
        ModulesRoot = (Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\Modules')
    }
    $ctx = Start-OneLinkBgJob -Script $script:SqlRunWorker -Vars $vars
    Write-OneLinkLog "[$($server.Host)] Running SQL script: $path" -Level Info
    Watch-OneLinkSqlRunJob -Ctx $ctx -Popup $popup -RunButton $BtnRunSqlScript -TargetHost ([string]$server.Host) -ScriptPath $path
}
$BtnRunSqlScript.Add_Click({ Invoke-OneLinkSqlScriptRun })

