# Strip ANSI/terminal control sequences so shell output shows as clean text in a
# plain WPF textbox. (A textbox is not a full terminal emulator, so full-screen
# apps like vim/top still won't render - this just keeps ordinary command output
# readable instead of littered with escape codes.)
function Remove-OneLinkAnsi {
    param([AllowEmptyString()][string]$Text)
    $t = [string]$Text
    $t = [regex]::Replace($t, "\x1B\[[0-9;?=]*[ -/]*[@-~]", '')   # CSI (colours, cursor moves)
    $t = [regex]::Replace($t, "\x1B\][^\x07\x1B]*(\x07|\x1B\\)", '') # OSC (title, etc.)
    $t = [regex]::Replace($t, "\x1B[@-Z\\-_]", '')                  # other single-char escapes
    $t = $t -replace "\x07", ''                                     # bell
    $t = $t -replace "\r", ''                                       # bare carriage returns
    return $t
}

# Detect a full-screen / interactive (curses) program that the plain-text
# console can't render and that would hijack all further input (nano, vim, top,
# less, man, ...). Returns the offending program name, or $null if the command
# is fine to run. Skips leading wrappers (sudo, env, VAR=val, nohup, ...) and
# checks every segment of a pipeline / '&&' / ';' chain.
function Test-OneLinkInteractiveCommand {
    param([string]$CommandLine)

    $interactive = @(
        'nano','pico','vi','vim','view','vimdiff','nvim','emacs','emacsclient','mcedit','micro','joe','jed','ne','ed',
        'top','htop','atop','btop','iotop','iftop','nmon','glances',
        'less','more','most','man',
        'watch','mc','ranger','vifm',
        'tmux','screen','byobu',
        'dialog','whiptail','nmtui','alsamixer',
        'tig','lynx','links','elinks','w3m','info','visudo'
    )
    $wrappers = @('sudo','env','nice','nohup','time','command','exec','builtin','stdbuf','setsid','\')

    foreach ($seg in ($CommandLine -split '(&&|\|\||;|\||&)')) {
        $s = $seg.Trim()
        if ($s -eq '' -or $s -in @('&&','||',';','|','&')) { continue }
        $tokens = @($s -split '\s+' | Where-Object { $_ -ne '' })
        if ($tokens.Count -eq 0) { continue }

        $i = 0
        while ($i -lt $tokens.Count) {
            $tok = $tokens[$i]
            if ($tok -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++; continue }   # VAR=value prefix
            if ($tok -in $wrappers) {
                $i++
                while ($i -lt $tokens.Count -and $tokens[$i].StartsWith('-')) {
                    if ($tokens[$i] -in @('-u','-g','-p')) { $i += 2 } else { $i++ }   # sudo -u user, etc.
                }
                continue
            }
            break
        }
        if ($i -ge $tokens.Count) { continue }

        $prog = ($tokens[$i] -split '/')[-1].ToLower()
        $rest = if ($i + 1 -le $tokens.Count - 1) { @($tokens[($i + 1)..($tokens.Count - 1)]) } else { @() }

        if ($prog -in $interactive) { return $prog }
        if ($prog -eq 'crontab'   -and ($rest -contains '-e'))   { return 'crontab -e' }
        if ($prog -eq 'systemctl' -and ($rest -contains 'edit')) { return 'systemctl edit' }
    }
    return $null
}

# ----------------------------------------------------------------------------
#  In-tool SSH Console
#  ---------------------------------------------------------------------------
#  A lightweight command console over the already-embedded Posh-SSH shell stream
#  (New-SSHShellStream) - NO extra dependency. It runs on a persistent PTY, so
#  cd / environment / passwordless sudo carry over between commands, and you can
#  run anything (touch, chmod, systemctl status, tail, ...). Output is polled on
#  a DispatcherTimer so the UI never blocks. It is NOT a full terminal emulator:
#  full-screen curses apps (vim, top, nano, less, dialog menus) won't render -
#  use PuTTY for those.
# ----------------------------------------------------------------------------
function Show-OneLinkSshConsole {
    param([object]$Server = $null)   # when set (e.g. from a server row's right-click), use that server directly
    $connected = @($script:Servers | Where-Object { $null -ne $_.Session -and -not [string]::IsNullOrWhiteSpace($_.Host) })
    if ($connected.Count -eq 0) {
        Show-WarningMessage "Connect to at least one server first, then open the SSH Console."
        return
    }
    if ($null -ne $Server) {
        if ($null -eq $Server.Session) { Show-WarningMessage "Connect to $($Server.Host) first, then open its console."; return }
        $connected = @($Server)
    }

    # Capture settings into a LOCAL so the closures below (GetNewClosure) see it -
    # inside a closure, $script:Settings resolves to the closure's own scope, not
    # the real script scope, so referencing it there would be $null.
    $settings = $script:Settings

    $win = New-Object System.Windows.Window
    $win.Title = 'SSH Console'
    $win.Width = 940; $win.Height = 640
    $win.MinWidth = 560; $win.MinHeight = 400
    $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5F7FB'))
    if ($script:Window) { $win.Owner = $script:Window }

    $grid = New-Object System.Windows.Controls.Grid
    # Rows: 0 header, 1 server, 2 output(*), 3 input
    foreach ($h in @('Auto', 'Auto', '*', 'Auto')) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = [System.Windows.GridLength]::new(1, $(if ($h -eq '*') { 'Star' } else { 'Auto' }))
        [void]$grid.RowDefinitions.Add($rd)
    }

    # Row 0: header
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = New-OneLinkHeaderBrush
    $hdr.Padding = '16,11'
    $htxt = New-Object System.Windows.Controls.TextBlock
    $htxt.Text = 'SSH Console'; $htxt.Foreground = [System.Windows.Media.Brushes]::White; $htxt.FontSize = 15; $htxt.FontWeight = 'Bold'
    $hdr.Child = $htxt
    [System.Windows.Controls.Grid]::SetRow($hdr, 0); [void]$grid.Children.Add($hdr)

    # Row 1: server + Clear
    $top = New-Object System.Windows.Controls.Grid
    $top.Margin = '12,12,12,4'
    foreach ($w in @('Auto', 'Auto', '*', 'Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = [System.Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } else { 'Auto' }))
        [void]$top.ColumnDefinitions.Add($cd)
    }
    $lblSrv = New-Object System.Windows.Controls.TextBlock
    $lblSrv.Text = 'Server:'; $lblSrv.VerticalAlignment = 'Center'; $lblSrv.Margin = '0,0,8,0'; $lblSrv.FontWeight = 'SemiBold'
    [System.Windows.Controls.Grid]::SetColumn($lblSrv, 0); [void]$top.Children.Add($lblSrv)

    $secondaryStyle = Get-OneLinkStyle 'SecondaryButtonStyle'
    $primaryStyle = Get-OneLinkStyle 'PrimaryButtonStyle'

    $cmbServer = $null
    if ($connected.Count -eq 1) {
        $lblSrvValue = New-Object System.Windows.Controls.TextBlock
        $lblSrvValue.Text = [string]$connected[0].Host
        $lblSrvValue.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($lblSrvValue, 1); [void]$top.Children.Add($lblSrvValue)
    }
    else {
        $cmbServer = New-Object System.Windows.Controls.ComboBox
        $cmbServer.Width = 200; $cmbServer.VerticalAlignment = 'Center'
        foreach ($s in $connected) { [void]$cmbServer.Items.Add([string]$s.Host) }
        $cmbServer.SelectedIndex = 0
        [System.Windows.Controls.Grid]::SetColumn($cmbServer, 1); [void]$top.Children.Add($cmbServer)
    }

    $btnClear = New-Object System.Windows.Controls.Button
    $btnClear.Content = 'Clear'; $btnClear.Width = 84; $btnClear.Height = 28
    if ($secondaryStyle) { $btnClear.Style = $secondaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnClear, 3); [void]$top.Children.Add($btnClear)
    [System.Windows.Controls.Grid]::SetRow($top, 1); [void]$grid.Children.Add($top)

    # Row 2: output (terminal-like)
    $card = New-Object System.Windows.Controls.Border
    $card.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#111827'))
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Margin = '12,4,12,6'
    $out = New-Object System.Windows.Controls.TextBox
    $out.IsReadOnly = $true; $out.AcceptsReturn = $true
    $out.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Courier New, monospace')
    $out.FontSize = 13; $out.TextWrapping = 'NoWrap'
    $out.VerticalScrollBarVisibility = 'Auto'; $out.HorizontalScrollBarVisibility = 'Auto'
    $out.BorderThickness = New-Object System.Windows.Thickness(0)
    $out.Padding = '12,10'
    $out.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#111827'))
    $out.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#D1FAE5'))
    $out.Text = ''
    $card.Child = $out
    [System.Windows.Controls.Grid]::SetRow($card, 2); [void]$grid.Children.Add($card)

    # Row 3: input + Run + Close
    $bottom = New-Object System.Windows.Controls.Grid
    $bottom.Margin = '12,2,12,12'
    foreach ($w in @('Auto', '*', 'Auto', 'Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = [System.Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } else { 'Auto' }))
        [void]$bottom.ColumnDefinitions.Add($cd)
    }
    $prompt = New-Object System.Windows.Controls.TextBlock
    $prompt.Text = '$'; $prompt.VerticalAlignment = 'Center'; $prompt.Margin = '2,0,8,0'; $prompt.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas'); $prompt.FontWeight = 'Bold'
    [System.Windows.Controls.Grid]::SetColumn($prompt, 0); [void]$bottom.Children.Add($prompt)
    $in = New-Object System.Windows.Controls.TextBox
    $in.VerticalAlignment = 'Center'; $in.Height = 28; $in.Margin = '0,0,8,0'; $in.VerticalContentAlignment = 'Center'; $in.Padding = '6,0'
    $in.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Courier New, monospace')
    $in.ToolTip = 'Type a command and press Enter (or click Run). Runs on a persistent shell, so cd and sudo carry over.'
    [System.Windows.Controls.Grid]::SetColumn($in, 1); [void]$bottom.Children.Add($in)
    $btnRun = New-Object System.Windows.Controls.Button
    $btnRun.Content = 'Run'; $btnRun.Width = 90; $btnRun.Height = 28; $btnRun.Margin = '0,0,8,0'
    if ($primaryStyle) { $btnRun.Style = $primaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnRun, 2); [void]$bottom.Children.Add($btnRun)
    $btnClose = New-Object System.Windows.Controls.Button
    $btnClose.Content = 'Close'; $btnClose.Width = 84; $btnClose.Height = 28; $btnClose.IsCancel = $true
    if ($secondaryStyle) { $btnClose.Style = $secondaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 3); [void]$bottom.Children.Add($btnClose)
    [System.Windows.Controls.Grid]::SetRow($bottom, 3); [void]$grid.Children.Add($bottom)

    $win.Content = $grid
    $recorder = Enable-OneLinkWindowRecorder $win

    # ---- state + shell stream (polled by a DispatcherTimer; UI never blocks) ----
    $state = @{ Stream = $null; Host = $null; Pending = (New-Object System.Collections.ArrayList); Buffer = ''; Timeout = [math]::Max(30, [int]$settings.Ssh.CommandTimeoutSeconds) }

    $resolveServer = {
        if ($null -ne $cmbServer) {
            $h = [string]$cmbServer.SelectedItem
            return ($connected | Where-Object { [string]$_.Host -eq $h } | Select-Object -First 1)
        }
        return $connected[0]
    }.GetNewClosure()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        if ($null -eq $state.Stream) { return }
        try {
            if ($state.Stream.DataAvailable) {
                $chunk = $state.Stream.Read()
                if (-not [string]::IsNullOrEmpty($chunk)) {
                    $out.AppendText([string](Update-OneLinkConsoleRecording -State $state -Chunk (Remove-OneLinkAnsi $chunk)))
                    $out.ScrollToEnd()
                }
            }
        }
        catch { Update-OneLinkConsoleRecording -State $state -Closing | Out-Null }
        $out.AppendText([string](Update-OneLinkConsoleRecording -State $state))
    }.GetNewClosure())

    $openStream = {
        $timer.Stop()
        Update-OneLinkConsoleRecording -State $state -Closing | Out-Null
        $state.Buffer = ''
        if ($null -ne $state.Stream) { try { $state.Stream.Dispose() } catch { } ; $state.Stream = $null }
        $srv = & $resolveServer
        if (-not $srv) { return }
        try {
            $state.Stream = New-OneLinkShellStream -Session $srv.Session -Settings $settings
            $state.Host = [string]$srv.Host
            # Neutralise pagers so commands that would normally open 'less'
            # (git log, journalctl, systemctl status, man, ...) just print their
            # output instead of hanging the console waiting for a pager.
            try { $state.Stream.WriteLine('export PAGER=cat GIT_PAGER=cat SYSTEMD_PAGER=cat MANPAGER=cat 2>/dev/null') } catch { }
            $out.AppendText("=== Connected to $($srv.Host). Type a command and press Enter. ===`r`n")
            $out.ScrollToEnd()
            $timer.Start()
            $in.Focus() | Out-Null
        }
        catch {
            Show-ErrorMessage "Could not open a shell on $($srv.Host): $($_.Exception.Message)"
        }
    }.GetNewClosure()

    $runCmd = {
        if ($null -eq $state.Stream) { Show-WarningMessage 'The console is not connected yet.'; return }
        $cmd = [string]$in.Text
        if ([string]::IsNullOrWhiteSpace($cmd)) { return }
        # Refuse full-screen / interactive programs the console can't render (they
        # would garble the output and capture all further input).
        $bad = Test-OneLinkInteractiveCommand $cmd
        if ($null -ne $bad) {
            $out.AppendText("`r`n[Command Console] '$bad' is an interactive / full-screen program and can't run in this console." +
                "`r`n  - To edit a file, use the 'Edit File' button." +
                "`r`n  - To view a file, try: cat <file>   (or: tail -n 100 <file>)." +
                "`r`n  - For anything full-screen (nano, vim, top, less, ...), use PuTTY.`r`n")
            $out.ScrollToEnd()
            $in.Clear()
            return
        }
        if (-not (Test-OneLinkRecorderCapture)) {
            try { $state.Stream.WriteLine($cmd) }
            catch { Show-ErrorMessage "Failed to send the command: $($_.Exception.Message)"; return }
            $in.Clear()
            return
        }
        $operation = Start-OneLinkRecordedOperation $recorder
        $token = 'OLK_METRIC_' + [guid]::NewGuid().ToString('N')
        $pending = @{ Token = $token; Host = $state.Host; Context = $operation }
        try {
            # A unique marker reports the shell's exit status after this command.
            # Keep the existing persistent shell; cd/export/sudo behavior is retained.
            $suffix = 'printf ''\n' + $token + ':%s\n'' "$?"'
            [void]$state.Pending.Add($pending)
            # Parse the marker on the same shell line so an interactive command
            # cannot consume a queued marker line as its input.
            $state.Stream.WriteLine('eval ' + (ConvertTo-OneLinkBashArg $cmd) + '; ' + $suffix)
        }
        catch {
            [void]$state.Pending.Remove($pending)
            Complete-OneLinkActivity -Name 'SSH Command' -Target ([string]$state.Host) -Outcome 'Failed' -Context $operation
            Show-ErrorMessage "Failed to send the command: $($_.Exception.Message)"; return
        }
        $in.Clear()
    }.GetNewClosure()

    $btnRun.Add_Click($runCmd)
    $in.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) { $e.Handled = $true; & $runCmd }
    }.GetNewClosure())
    $btnClear.Add_Click({ $out.Clear(); Complete-OneLinkActivity -Name 'Clear SSH Console' -Target ([string]$state.Host) -Context $recorder }.GetNewClosure())
    if ($null -ne $cmbServer) { $cmbServer.Add_SelectionChanged({ $out.Clear(); & $openStream }.GetNewClosure()) }

    $btnClose.Add_Click({ $win.Close() }.GetNewClosure())

    $win.Add_ContentRendered({ & $openStream }.GetNewClosure())
    $win.Add_Closed({
        try { $timer.Stop() } catch { }
        Complete-OneLinkActivity -Name 'Close SSH Console' -Target ([string]$state.Host) -Outcome 'Closed' -Context $recorder
        Update-OneLinkConsoleRecording -State $state -Closing | Out-Null
        if ($null -ne $state.Stream) { try { $state.Stream.Dispose() } catch { } ; $state.Stream = $null }
    }.GetNewClosure())

    # Non-modal: keep the console open while you use the rest of Foreman (and open
    # more than one - e.g. a console per server).
    [void]$win.Show()
}

