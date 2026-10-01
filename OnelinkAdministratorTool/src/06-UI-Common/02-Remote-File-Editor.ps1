# ----------------------------------------------------------------------------
#  Generic "Edit File" popup
#  ---------------------------------------------------------------------------
#  Open ANY file on a connected server, edit it in place, and save it back.
#  - Reads with sudo (so root-owned files are visible) and transports the
#    content as base64 so arbitrary bytes/quotes survive the round trip.
#  - Saves via 'sudo tee' onto the existing inode, which PRESERVES the file's
#    owner and permission bits (tee never chmod/chown's). A timestamped .bak
#    backup is made first.
#  - If exactly ONE server is connected it is used automatically (no picker);
#    with more than one connected, a server dropdown is shown.
# ----------------------------------------------------------------------------
function Show-OneLinkFileEditor {
    param([object]$Server = $null)   # when set (e.g. from a server row's right-click), use that server directly
    $connected = @($script:Servers | Where-Object { $null -ne $_.Session -and -not [string]::IsNullOrWhiteSpace($_.Host) })
    if ($connected.Count -eq 0) {
        Show-WarningMessage "Connect to at least one server first, then use Edit File."
        return
    }
    if ($null -ne $Server) {
        if ($null -eq $Server.Session) { Show-WarningMessage "Connect to $($Server.Host) first, then edit a file on it."; return }
        $connected = @($Server)
    }

    # Capture settings into a LOCAL so the closures below (GetNewClosure) see it -
    # inside a closure $script:Settings resolves to the closure's own (empty) scope.
    $settings = $script:Settings

    $win = New-Object System.Windows.Window
    $win.Title = 'Edit File'
    $win.Width = 900; $win.Height = 640
    $win.MinWidth = 560; $win.MinHeight = 420
    $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5F7FB'))
    if ($script:Window) { $win.Owner = $script:Window }

    $grid = New-Object System.Windows.Controls.Grid
    # Rows: 0 header, 1 server+path, 2 search-results, 3 editor(*), 4 restart, 5 buttons
    foreach ($h in @('Auto', 'Auto', 'Auto', '*', 'Auto', 'Auto')) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = [System.Windows.GridLength]::new(1, $(if ($h -eq '*') { 'Star' } else { 'Auto' }))
        [void]$grid.RowDefinitions.Add($rd)
    }

    # Row 0: header
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = New-OneLinkHeaderBrush
    $hdr.Padding = '16,11'
    $htxt = New-Object System.Windows.Controls.TextBlock
    $htxt.Text = 'Edit File'; $htxt.Foreground = [System.Windows.Media.Brushes]::White; $htxt.FontSize = 15; $htxt.FontWeight = 'Bold'
    $hdr.Child = $htxt
    [System.Windows.Controls.Grid]::SetRow($hdr, 0); [void]$grid.Children.Add($hdr)

    # Row 1: server + path + Find + Load
    $top = New-Object System.Windows.Controls.Grid
    $top.Margin = '12,12,12,4'
    foreach ($w in @('Auto', 'Auto', '*', 'Auto', 'Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = [System.Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } else { 'Auto' }))
        [void]$top.ColumnDefinitions.Add($cd)
    }

    $lblSrv = New-Object System.Windows.Controls.TextBlock
    $lblSrv.Text = 'Server:'; $lblSrv.VerticalAlignment = 'Center'; $lblSrv.Margin = '0,0,8,0'; $lblSrv.FontWeight = 'SemiBold'
    [System.Windows.Controls.Grid]::SetColumn($lblSrv, 0); [void]$top.Children.Add($lblSrv)

    $cmbServer = $null
    $lblSrvValue = $null
    if ($connected.Count -eq 1) {
        # Single server: no picker, just show it.
        $lblSrvValue = New-Object System.Windows.Controls.TextBlock
        $lblSrvValue.Text = [string]$connected[0].Host
        $lblSrvValue.VerticalAlignment = 'Center'; $lblSrvValue.Margin = '0,0,14,0'
        [System.Windows.Controls.Grid]::SetColumn($lblSrvValue, 1); [void]$top.Children.Add($lblSrvValue)
    }
    else {
        $cmbServer = New-Object System.Windows.Controls.ComboBox
        $cmbServer.Width = 190; $cmbServer.Margin = '0,0,14,0'; $cmbServer.VerticalAlignment = 'Center'
        foreach ($s in $connected) { [void]$cmbServer.Items.Add([string]$s.Host) }
        $cmbServer.SelectedIndex = 0
        [System.Windows.Controls.Grid]::SetColumn($cmbServer, 1); [void]$top.Children.Add($cmbServer)
    }

    $txtPath = New-Object System.Windows.Controls.TextBox
    $txtPath.VerticalAlignment = 'Center'; $txtPath.Height = 26; $txtPath.Margin = '0,0,8,0'
    $txtPath.VerticalContentAlignment = 'Center'; $txtPath.Padding = '6,0'
    $txtPath.ToolTip = "Full path of the file to edit (e.g. /opt/onelink-concentrator/conf/activemq.xml)." + [Environment]::NewLine +
        "Don't know the path? Type just the file name (e.g. activemq.xml or *.properties) and click Find."
    [System.Windows.Controls.Grid]::SetColumn($txtPath, 2); [void]$top.Children.Add($txtPath)

    $secondaryStyle = Get-OneLinkStyle 'SecondaryButtonStyle'
    $primaryStyle = Get-OneLinkStyle 'PrimaryButtonStyle'

    $btnFind = New-Object System.Windows.Controls.Button
    $btnFind.Content = 'Find'; $btnFind.Width = 84; $btnFind.Height = 28; $btnFind.Margin = '0,0,8,0'
    $btnFind.ToolTip = "Search the server for a file by name when you don't know its full path. Type a name or wildcard (e.g. server.xml or *.properties)."
    if ($secondaryStyle) { $btnFind.Style = $secondaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnFind, 3); [void]$top.Children.Add($btnFind)

    $btnLoad = New-Object System.Windows.Controls.Button
    $btnLoad.Content = 'Load'; $btnLoad.Width = 90; $btnLoad.Height = 28
    if ($secondaryStyle) { $btnLoad.Style = $secondaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnLoad, 4); [void]$top.Children.Add($btnLoad)

    [System.Windows.Controls.Grid]::SetRow($top, 1); [void]$grid.Children.Add($top)

    # Row 2: search results (hidden until a Find runs)
    $matchRow = New-Object System.Windows.Controls.Grid
    $matchRow.Margin = '12,0,12,4'; $matchRow.Visibility = [System.Windows.Visibility]::Collapsed
    foreach ($w in @('Auto', '*')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = [System.Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } else { 'Auto' }))
        [void]$matchRow.ColumnDefinitions.Add($cd)
    }
    $lblMatch = New-Object System.Windows.Controls.TextBlock
    $lblMatch.Text = 'Found:'; $lblMatch.VerticalAlignment = 'Center'; $lblMatch.Margin = '0,0,8,0'; $lblMatch.FontWeight = 'SemiBold'
    [System.Windows.Controls.Grid]::SetColumn($lblMatch, 0); [void]$matchRow.Children.Add($lblMatch)
    $cmbMatches = New-Object System.Windows.Controls.ComboBox
    $cmbMatches.VerticalAlignment = 'Center'
    $cmbMatches.ToolTip = 'Files found on the server. Pick one to load it into the editor.'
    [System.Windows.Controls.Grid]::SetColumn($cmbMatches, 1); [void]$matchRow.Children.Add($cmbMatches)
    [System.Windows.Controls.Grid]::SetRow($matchRow, 2); [void]$grid.Children.Add($matchRow)

    # Row 3: editor
    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.Brushes]::White
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E2E8F0'))
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Margin = '12,4,12,6'
    $editor = New-Object System.Windows.Controls.TextBox
    $editor.AcceptsReturn = $true; $editor.AcceptsTab = $true; $editor.IsReadOnly = $true
    $editor.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Courier New, monospace')
    $editor.FontSize = 13; $editor.TextWrapping = 'NoWrap'
    $editor.VerticalScrollBarVisibility = 'Auto'; $editor.HorizontalScrollBarVisibility = 'Auto'
    $editor.BorderThickness = New-Object System.Windows.Thickness(0)
    $editor.Padding = '14,12'; $editor.Background = [System.Windows.Media.Brushes]::White
    $editor.Text = '(Enter a file path and click Load.)'
    $card.Child = $editor
    [System.Windows.Controls.Grid]::SetRow($card, 3); [void]$grid.Children.Add($card)

    # Row 4: restart-service option
    $opt = New-Object System.Windows.Controls.StackPanel
    $opt.Orientation = 'Horizontal'; $opt.Margin = '12,0,12,4'; $opt.VerticalAlignment = 'Center'
    $chkRestart = New-Object System.Windows.Controls.CheckBox
    $chkRestart.Content = 'Restart service after save:'; $chkRestart.VerticalAlignment = 'Center'; $chkRestart.Margin = '0,0,8,0'
    [void]$opt.Children.Add($chkRestart)
    $cmbService = New-Object System.Windows.Controls.ComboBox
    $cmbService.Width = 220; $cmbService.VerticalAlignment = 'Center'; $cmbService.IsEnabled = $false
    [void]$opt.Children.Add($cmbService)
    [System.Windows.Controls.Grid]::SetRow($opt, 4); [void]$grid.Children.Add($opt)

    # Row 5: buttons + status
    $bottom = New-Object System.Windows.Controls.Grid
    $bottom.Margin = '12,2,12,12'
    foreach ($w in @('*', 'Auto', 'Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = [System.Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } else { 'Auto' }))
        [void]$bottom.ColumnDefinitions.Add($cd)
    }
    $lblStatus = New-Object System.Windows.Controls.TextBlock
    $lblStatus.VerticalAlignment = 'Center'; $lblStatus.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#475569'))
    $lblStatus.TextTrimming = 'CharacterEllipsis'
    [System.Windows.Controls.Grid]::SetColumn($lblStatus, 0); [void]$bottom.Children.Add($lblStatus)
    $btnSave = New-Object System.Windows.Controls.Button
    $btnSave.Content = 'Save'; $btnSave.Width = 100; $btnSave.Height = 28; $btnSave.Margin = '0,0,8,0'; $btnSave.IsEnabled = $false
    if ($primaryStyle) { $btnSave.Style = $primaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnSave, 1); [void]$bottom.Children.Add($btnSave)
    $btnClose = New-Object System.Windows.Controls.Button
    $btnClose.Content = 'Close'; $btnClose.Width = 90; $btnClose.Height = 28; $btnClose.IsCancel = $true
    if ($secondaryStyle) { $btnClose.Style = $secondaryStyle }
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 2); [void]$bottom.Children.Add($btnClose)
    [System.Windows.Controls.Grid]::SetRow($bottom, 5); [void]$grid.Children.Add($bottom)

    $win.Content = $grid
    $recorder = Enable-OneLinkWindowRecorder $win

    # ---- shared state (mutated inside closures via hashtable members) ----
    $state = @{ Loaded = $false; Path = $null; Host = $null; SuppressMatch = $false }

    $resolveServer = {
        if ($null -ne $cmbServer) {
            $h = [string]$cmbServer.SelectedItem
            return ($connected | Where-Object { [string]$_.Host -eq $h } | Select-Object -First 1)
        }
        return $connected[0]
    }.GetNewClosure()

    $populateServices = {
        $cmbService.Items.Clear()
        $srv = & $resolveServer
        if ($srv -and $srv.Services) {
            foreach ($svc in $srv.Services) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = [string]$svc.DisplayName
                $item.Tag = [string]$svc.SystemdName
                [void]$cmbService.Items.Add($item)
            }
        }
        if ($cmbService.Items.Count -gt 0) { $cmbService.SelectedIndex = 0 }
    }.GetNewClosure()
    & $populateServices

    if ($null -ne $cmbServer) {
        $cmbServer.Add_SelectionChanged({
            # Switching server invalidates the loaded content and any search hits.
            $state.Loaded = $false
            $btnSave.IsEnabled = $false
            $editor.IsReadOnly = $true
            $editor.Text = '(Server changed - click Load to read the file from this server.)'
            $lblStatus.Text = ''
            $state.SuppressMatch = $true
            $cmbMatches.Items.Clear()
            $state.SuppressMatch = $false
            $matchRow.Visibility = [System.Windows.Visibility]::Collapsed
            & $populateServices
        }.GetNewClosure())
    }

    $chkRestart.Add_Checked({ $cmbService.IsEnabled = $true }.GetNewClosure())
    $chkRestart.Add_Unchecked({ $cmbService.IsEnabled = $false }.GetNewClosure())

    # ---- Load ----
    $btnLoad.Add_Click({
        $path = ([string]$txtPath.Text).Trim()
        if ([string]::IsNullOrWhiteSpace($path)) { Show-WarningMessage 'Enter the full path of the file to edit.'; return }
        $srv = & $resolveServer
        if (-not $srv) { Show-WarningMessage 'No connected server selected.'; return }

        $operation = Start-OneLinkRecordedOperation $recorder
        $outcome = 'Failed'
        $remoteSeconds = $null
        $win.Cursor = [Windows.Input.Cursors]::Wait
        try {
            $tmpl = @'
F=__PATH__
if sudo -n test -f "$F" 2>/dev/null || test -f "$F" 2>/dev/null; then
  if sudo -n base64 -w0 "$F" 2>/dev/null; then echo; echo OLK_EDIT_OK
  elif base64 -w0 "$F" 2>/dev/null; then echo; echo OLK_EDIT_OK
  else echo OLK_EDIT_DENIED; fi
elif sudo -n test -e "$F" 2>/dev/null || test -e "$F" 2>/dev/null; then
  echo OLK_EDIT_NOTFILE
else
  echo OLK_EDIT_NOPATH
fi
'@
            $cmd = $tmpl.Replace('__PATH__', (ConvertTo-OneLinkBashArg $path))
            $res = Invoke-OneLinkSshCommand -Session $srv.Session -Command $cmd -TimeoutSeconds 60
            $remoteSeconds = ((Get-Date) - $operation.Started).TotalSeconds
            $out = [string]$res.Output
            $lines = @($out -split "`r?`n")

            if ($lines -contains 'OLK_EDIT_NOPATH') {
                Show-WarningMessage "No such file on $($srv.Host):`n$path"
                return
            }
            if ($lines -contains 'OLK_EDIT_NOTFILE') {
                Show-WarningMessage "That path exists but is not a regular file (it may be a directory):`n$path"
                return
            }
            if ($lines -contains 'OLK_EDIT_DENIED') {
                Show-WarningMessage "Permission denied reading '$path' on $($srv.Host). The account needs sudo rights to read this file."
                return
            }
            $okIdx = [array]::IndexOf($lines, 'OLK_EDIT_OK')
            if ($okIdx -lt 0) {
                Show-ErrorMessage "Could not read the file. Server response:`n$out"
                return
            }
            $b64 = ($lines[0..($okIdx - 1)] -join '').Trim()
            $text = ''
            if ($b64.Length -gt 0) {
                $bytes = $null
                try { $bytes = [Convert]::FromBase64String($b64) }
                catch { Show-ErrorMessage "The file content could not be read from the server."; return }
                # A NUL byte means the file is binary; editing it as text would
                # corrupt it on save, so refuse. Any TEXT file (regardless of
                # extension - .java, .py, .xml, .conf, .html, .sh, .txt, ...)
                # is fine.
                if ($bytes -contains [byte]0) {
                    Show-WarningMessage "'$path' looks like a binary file (it contains non-text data), so it can't be edited safely as text.`n`nUse Edit File for text-based files of any type (e.g. .xml, .properties, .conf, .java, .py, .sh, .txt, .html, .json, .yaml)."
                    return
                }
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            }
            # Show with Windows line endings for comfortable editing.
            $editor.Text = ($text -replace "`r?`n", "`r`n")
            $editor.IsReadOnly = $false
            $btnSave.IsEnabled = $true
            $outcome = 'Success'
            $state.Loaded = $true
            $state.Path = $path
            $state.Host = [string]$srv.Host
            $lblStatus.Text = "Loaded from $($srv.Host):$path"
            Write-OneLinkLog "[$($srv.Host)] Edit File: loaded '$path' ($($text.Length) chars)." -Level Info
        }
        catch {
            Show-ErrorMessage "Failed to load the file: $($_.Exception.Message)"
        }
        finally {
            $win.Cursor = $null
            if ($null -eq $remoteSeconds) { $remoteSeconds = ((Get-Date) - $operation.Started).TotalSeconds }
            Complete-OneLinkActivity -Name 'Load File' -Target ([string]$srv.Host) -Outcome $outcome -OperationSeconds $remoteSeconds -Context $operation
            $recorder.Last = Get-Date
        }
    }.GetNewClosure())

    # ---- Find on server (locate a file by name when the path is unknown) ----
    $btnFind.Add_Click({
        $raw = ([string]$txtPath.Text).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { Show-WarningMessage "Type a file name (or wildcard, e.g. *.properties) to search for, then click Find."; return }
        # Search by the file NAME only (drop any directory the user pasted).
        $name = if ($raw -match '/') { ($raw -split '/')[-1] } else { $raw }
        if ([string]::IsNullOrWhiteSpace($name)) { Show-WarningMessage "Enter a file name to search for."; return }
        $srv = & $resolveServer
        if (-not $srv) { Show-WarningMessage 'No connected server selected.'; return }

        # A wildcard search (*, ?) is taken literally; a plain name is matched
        # loosely (ignoring spaces, brackets/parens and case). For the loose case
        # we cast a WIDE net on the server using the longest alphanumeric chunk of
        # the name as a substring glob, then filter locally by the loose key so
        # "license 3.lic" also finds "license (3).lic", "license(3).lic", etc.
        $isWildcard = ($name -match '[\*\?]')
        if ($isWildcard) {
            $glob = $name
        }
        else {
            $chunks = @([regex]::Matches($name, '[A-Za-z0-9]+') | ForEach-Object { $_.Value })
            $anchor = if ($chunks.Count -gt 0) { ($chunks | Sort-Object { $_.Length } -Descending | Select-Object -First 1) } else { $name }
            $glob = "*$anchor*"
        }
        # Loose key of what the user typed (drop extension separately so a name
        # typed without an extension can still match files that have one).
        $typedHasExt = ($name -match '\.[^.\\/]+$')
        $typedKey     = ConvertTo-OneLinkLooseKey $name
        $typedKeyNoExt = ConvertTo-OneLinkLooseKey ($name -replace '\.[^.\\/]+$', '')

        $operation = Start-OneLinkRecordedOperation $recorder
        $outcome = 'Failed'
        $remoteSeconds = $null
        $win.Cursor = [Windows.Input.Cursors]::Wait
        $lblStatus.Text = "Searching $($srv.Host) for '$name'..."
        try {
            # Search the whole filesystem, pruning virtual/volatile trees for speed.
            # Case-insensitive; the glob is passed as a single quoted arg so it is
            # expanded by find, not the shell.
            $tmpl = @'
N=__NAME__
R=$( { sudo -n find / \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap -o -path /var/lib/docker \) -prune -o -type f -iname "$N" -print 2>/dev/null || find / \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap -o -path /var/lib/docker \) -prune -o -type f -iname "$N" -print 2>/dev/null ; } | sort -u | head -n 500 )
if [ -n "$R" ]; then printf '%s\n' "$R"; else echo OLK_FIND_NONE; fi
echo OLK_FIND_DONE
'@
            $cmd = $tmpl.Replace('__NAME__', (ConvertTo-OneLinkBashArg $glob))
            $res = Invoke-OneLinkSshCommand -Session $srv.Session -Command $cmd -TimeoutSeconds 150
            $remoteSeconds = ((Get-Date) - $operation.Started).TotalSeconds
            $out = [string]$res.Output
            $lines = @($out -split "`r?`n")
            $doneIdx = [array]::IndexOf($lines, 'OLK_FIND_DONE')
            if ($doneIdx -ge 0) { $outcome = 'Success' }
            $body = if ($doneIdx -ge 0) { @($lines[0..([Math]::Max(0,$doneIdx-1))]) } else { $lines }
            $candidates = @($body | Where-Object { $_ -match '^/' } )

            # For a plain name, keep only candidates whose file name matches the
            # loose key (wildcard searches keep every hit as-is).
            if ($isWildcard) {
                $found = $candidates
            }
            else {
                $found = @($candidates | Where-Object {
                    $leaf = ($_ -split '/')[-1]
                    if ($typedHasExt) {
                        (ConvertTo-OneLinkLooseKey $leaf) -eq $typedKey
                    }
                    else {
                        # user gave no extension: compare against the file name with
                        # its extension stripped, so "license (3)" matches "license (3).lic".
                        (ConvertTo-OneLinkLooseKey ($leaf -replace '\.[^.\\/]+$', '')) -eq $typedKeyNoExt
                    }
                })
            }

            if ($found.Count -eq 0 -or ($body -contains 'OLK_FIND_NONE')) {
                $matchRow.Visibility = [System.Windows.Visibility]::Collapsed
                $lblStatus.Text = ''
                Show-WarningMessage "No file matching '$name' was found on $($srv.Host)."
                return
            }

            $state.SuppressMatch = $true
            $cmbMatches.Items.Clear()
            foreach ($f in $found) { [void]$cmbMatches.Items.Add([string]$f) }
            $cmbMatches.SelectedIndex = -1
            $state.SuppressMatch = $false
            $matchRow.Visibility = [System.Windows.Visibility]::Visible
            $lblStatus.Text = "Found $($found.Count) match(es) on $($srv.Host) - pick one to load it."
            Write-OneLinkLog "[$($srv.Host)] Edit File: found $($found.Count) file(s) named '$name'." -Level Info
            if ($found.Count -eq 1) {
                # Exactly one hit: select it so the user can just click Load (or it auto-loads).
                $cmbMatches.SelectedIndex = 0
            }
        }
        catch {
            Show-ErrorMessage "Search failed on $($srv.Host): $($_.Exception.Message)"
        }
        finally {
            $win.Cursor = $null
            if ($null -eq $remoteSeconds) { $remoteSeconds = ((Get-Date) - $operation.Started).TotalSeconds }
            Complete-OneLinkActivity -Name 'Find File' -Target ([string]$srv.Host) -Outcome $outcome -OperationSeconds $remoteSeconds -Context $operation
            $recorder.Last = Get-Date
        }
    }.GetNewClosure())

    # Picking a match fills the path box and loads that file.
    $cmbMatches.Add_SelectionChanged({
        if ($state.SuppressMatch) { return }
        $sel = [string]$cmbMatches.SelectedItem
        if ([string]::IsNullOrWhiteSpace($sel)) { return }
        $txtPath.Text = $sel
        $btnLoad.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }.GetNewClosure())

    # Enter in the path box: an absolute path (with no wildcard) loads directly;
    # anything else (a bare name or a wildcard) triggers a Find.
    $txtPath.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $e.Handled = $true
            $t = ([string]$txtPath.Text).Trim()
            if ($t -match '^/' -and $t -notmatch '[\*\?]') {
                $btnLoad.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
            else {
                $btnFind.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }
    }.GetNewClosure())

    # ---- Save ----
    $btnSave.Add_Click({
        if (-not $state.Loaded) { Show-WarningMessage 'Load a file before saving.'; return }
        $srv = & $resolveServer
        if (-not $srv -or [string]$srv.Host -ne $state.Host) {
            Show-WarningMessage 'The selected server changed since the file was loaded. Click Load again first.'
            return
        }
        $path = $state.Path

        $svcName = $null
        if ($chkRestart.IsChecked) {
            if ($cmbService.SelectedItem -and $cmbService.SelectedItem.Tag) { $svcName = [string]$cmbService.SelectedItem.Tag }
            if ([string]::IsNullOrWhiteSpace($svcName)) { Show-WarningMessage 'Choose a service to restart, or untick the restart option.'; return }
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "Save changes to:`n$($srv.Host):$path`n`nA backup (.bak) will be made first and the file's owner and permissions will be preserved." +
            $(if ($svcName) { "`n`nThe service '$svcName' will be restarted after saving." } else { '' }),
            "$($script:AppName) - confirm save", 'OKCancel', 'Question')
        if ($confirm -ne [System.Windows.MessageBoxResult]::OK) { return }

        # Normalise to Unix line endings before writing to the Linux file.
        $content = ($editor.Text -replace "`r`n", "`n")
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

        $operation = Start-OneLinkRecordedOperation $recorder
        $outcome = 'Failed'
        $saveSeconds = 0.0
        $win.Cursor = [Windows.Input.Cursors]::Wait
        try {
            $tmpl = @'
F=__PATH__
B=__B64__
TS=$(date +%Y%m%d%H%M%S)
{ sudo -n cp -p -f "$F" "$F.bak.$TS" 2>/dev/null || cp -p -f "$F" "$F.bak.$TS" 2>/dev/null; } || true
{ sudo -n cp -p -f "$F" "$F.bak" 2>/dev/null || cp -p -f "$F" "$F.bak" 2>/dev/null; } || true
if printf '%s' "$B" | base64 -d | { sudo -n tee "$F" >/dev/null 2>&1 || tee "$F" >/dev/null 2>&1; }; then
  echo OLK_SAVE_OK
else
  echo OLK_SAVE_FAIL
fi
'@
            $cmd = $tmpl.Replace('__PATH__', (ConvertTo-OneLinkBashArg $path)).Replace('__B64__', (ConvertTo-OneLinkBashArg $b64))
            $res = Invoke-OneLinkSshCommand -Session $srv.Session -Command $cmd -TimeoutSeconds 90
            $saveSeconds = ((Get-Date) - $operation.Started).TotalSeconds
            $out = [string]$res.Output
            if (($out -split "`r?`n") -notcontains 'OLK_SAVE_OK') {
                Show-ErrorMessage "Save failed on $($srv.Host). Server response:`n$out`n$($res.Error)"
                return
            }
            Write-OneLinkLog "[$($srv.Host)] Edit File: saved '$path' (backup '$path.bak' created; owner/permissions preserved)." -Level Success

            $outcome = 'Success'
            if ($svcName) {
                $restartStart = Get-Date
                $restartOutcome = 'Failed'
                try {
                    Invoke-NMenuServiceAction -Session $srv.Session -Settings $settings -SystemdName $svcName -Action Restart | Out-Null
                    Write-OneLinkLog "[$($srv.Host)] Edit File: restarted service '$svcName' after save." -Level Success
                    $restartOutcome = 'Success'
                    $restartSeconds = ((Get-Date) - $restartStart).TotalSeconds
                    $lblStatus.Text = "Saved and restarted '$svcName' on $($srv.Host)."
                    Show-InfoMessage "Saved '$path' on $($srv.Host) and restarted '$svcName'.`nA backup was written to '$path.bak'."
                }
                catch {
                    Write-OneLinkLog "[$($srv.Host)] Edit File: save OK but service restart failed: $($_.Exception.Message)" -Level Warning
                    $outcome = 'Partial'
                    $restartSeconds = ((Get-Date) - $restartStart).TotalSeconds
                    $lblStatus.Text = "Saved on $($srv.Host); service restart failed."
                    Show-WarningMessage "The file was saved, but restarting '$svcName' failed:`n$($_.Exception.Message)"
                }
                finally {
                    $restartContext = @{ Clicks = 0; Fields = @(); ActiveSeconds = 0; Generation = $operation.Generation; Frozen = $true }
                    Complete-OneLinkActivity -Name ("Restart service ($svcName)") -Target ([string]$srv.Host) -Outcome $restartOutcome -OperationSeconds $restartSeconds -Context $restartContext
                }
            }
            else {
                $lblStatus.Text = "Saved to $($srv.Host):$path (backup: $path.bak)"
                Show-InfoMessage "Saved '$path' on $($srv.Host).`nA backup was written to '$path.bak'."
            }
        }
        catch {
            if ($saveSeconds -eq 0) { $saveSeconds = ((Get-Date) - $operation.Started).TotalSeconds }
            Show-ErrorMessage "Failed to save the file: $($_.Exception.Message)"
        }
        finally {
            $win.Cursor = $null
            Complete-OneLinkActivity -Name 'Save File' -Target ([string]$srv.Host) -Outcome $outcome -OperationSeconds $saveSeconds -Context $operation
            $recorder.Last = Get-Date
        }
    }.GetNewClosure())

    $win.Add_Closed({ Complete-OneLinkActivity -Name 'Close File Editor' -Target ([string]$state.Host) -Outcome 'Closed' -Context $recorder }.GetNewClosure())
    $btnClose.Add_Click({ $win.Close() }.GetNewClosure())

    # Non-modal: keep it open while you use the rest of Foreman (and open more than one).
    [void]$win.Show()
}

