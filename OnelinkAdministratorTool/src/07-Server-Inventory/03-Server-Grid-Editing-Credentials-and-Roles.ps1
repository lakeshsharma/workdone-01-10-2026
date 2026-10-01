# ----------------------------------------------------------------------------
#  Server-list management (editable grid)
# ----------------------------------------------------------------------------

# Add a blank editable row.
$BtnAddServer.Add_Click({
    $script:Servers.Add([OlServer]::new())
    Invoke-GridRefresh $ServerGrid
    Update-ConnectionSummary
    Complete-OneLinkActivity -Name 'Add Server Row'
})

$BtnSameCreds.Add_Click({ Set-OlServerCredentialsForAll })

$BtnRemoveServer.Add_Click({
    $all = @($script:Servers)
    if ($all.Count -eq 0) { Show-InfoMessage "There are no server rows to clear."; return }
    $confirm = [System.Windows.MessageBox]::Show(
        "Remove ALL $($all.Count) server row(s) from the list?`n`nAny open connections will be disconnected.",
        "$($script:AppName) - clear all", 'OKCancel', 'Question')
    if ($confirm -ne [System.Windows.MessageBoxResult]::OK) { return }
    foreach ($server in $all) {
        if ($null -ne $server.Session) {
            try { Disconnect-OneLinkSsh -Session $server.Session } catch { }
        }
    }
    $removedHosts = ($all | ForEach-Object { $_.Host }) -join ', '
    $script:Servers.Clear()
    Invoke-GridRefresh $ServerGrid
    Update-TargetCombos
    Update-DbTargetCombo
    Update-ConnectionSummary
    Update-ServiceChecklist
    Complete-OneLinkActivity -Name 'Clear All Servers' -Target $removedHosts
    Write-OneLinkLog "Cleared all server rows." -Level Info
})

# Small modal to capture a masked password for one row.
function Set-OlServerPassword {
    param([Parameter(Mandatory)][OlServer]$Server)

    $dlg = New-Object System.Windows.Window
    $dlg.Title = 'Set password'
    $dlg.Width = 380; $dlg.SizeToContent = 'Height'
    $dlg.WindowStartupLocation = 'CenterOwner'; $dlg.Owner = $script:Window; $dlg.ResizeMode = 'NoResize'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = '14'
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = "SSH password for $($Server.Host):"
    $lbl.Margin = '0,0,0,6'
    [void]$panel.Children.Add($lbl)

    # Masked box and a plain box occupy the same spot; the "Show password"
    # toggle swaps which one is visible so the user can verify what they typed.
    $inputGrid = New-Object System.Windows.Controls.Grid
    $pb = New-Object System.Windows.Controls.PasswordBox
    $pb.Height = 28
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Height = 28
    $tb.Visibility = [System.Windows.Visibility]::Collapsed
    $tb.VerticalContentAlignment = 'Center'

    # Pre-fill both with the current password so it can be reviewed on reopen.
    $existing = ConvertFrom-OneLinkSecure $Server.SecurePassword
    if (-not [string]::IsNullOrEmpty($existing)) { $pb.Password = $existing; $tb.Text = $existing }

    [void]$inputGrid.Children.Add($pb)
    [void]$inputGrid.Children.Add($tb)
    [void]$panel.Children.Add($inputGrid)

    $show = New-Object System.Windows.Controls.CheckBox
    $show.Content = 'Show password'
    $show.Margin = '0,8,0,0'
    $show.Add_Checked({
        $tb.Text = $pb.Password
        $tb.Visibility = [System.Windows.Visibility]::Visible
        $pb.Visibility = [System.Windows.Visibility]::Collapsed
        $tb.Focus() | Out-Null
    })
    $show.Add_Unchecked({
        $pb.Password = $tb.Text
        $pb.Visibility = [System.Windows.Visibility]::Visible
        $tb.Visibility = [System.Windows.Visibility]::Collapsed
        $pb.Focus() | Out-Null
    })
    [void]$panel.Children.Add($show)

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,12,0,0'
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = 'OK'; $ok.Width = 80; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Width = 80; $cancel.IsCancel = $true
    $ok.Add_Click({ $dlg.DialogResult = $true })
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($cancel)
    [void]$panel.Children.Add($btns)
    $dlg.Content = $panel
    $recorder = Enable-OneLinkWindowRecorder $dlg
    $pb.Focus() | Out-Null

    if ($dlg.ShowDialog()) {
        # Read from whichever box is currently visible.
        $plain = if ($show.IsChecked) { $tb.Text } else { $pb.Password }
        if (-not [string]::IsNullOrEmpty($plain)) {
            $sec = New-Object System.Security.SecureString
            foreach ($ch in $plain.ToCharArray()) { $sec.AppendChar($ch) }
            $sec.MakeReadOnly()
            $Server.SecurePassword = $sec
            $Server.PasswordDisplay = ([string][char]0x25CF) * 6
        }
        else {
            $Server.SecurePassword = $null
            $Server.PasswordDisplay = 'Set...'
        }
        Invoke-GridRefresh $ServerGrid
        Complete-OneLinkActivity -Name 'Set Server Password' -Target ([string]$Server.Host) -Context $recorder
    }
}

# Set ONE username and/or password and apply it to every server row (or just the
# selected rows) - saves setting the same credentials on many identical servers.
function Set-OlServerCredentialsForAll {
    if ($script:Servers.Count -eq 0) { Show-ErrorMessage "Add at least one server row first."; return }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = 'Same login for all servers'
    $dlg.Width = 430; $dlg.SizeToContent = 'Height'
    $dlg.WindowStartupLocation = 'CenterOwner'; $dlg.Owner = $script:Window; $dlg.ResizeMode = 'NoResize'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = '16'
    $intro = New-Object System.Windows.Controls.TextBlock
    $intro.Text = "Enter a username and/or password to apply to the server rows below. Leave a field blank to keep the existing value."
    $intro.TextWrapping = 'Wrap'; $intro.Margin = '0,0,0,12'
    [void]$panel.Children.Add($intro)

    $userLbl = New-Object System.Windows.Controls.TextBlock
    $userLbl.Text = 'Username'; $userLbl.Margin = '0,0,0,3'
    [void]$panel.Children.Add($userLbl)
    $userBox = New-Object System.Windows.Controls.TextBox
    $userBox.Height = 28; $userBox.VerticalContentAlignment = 'Center'; $userBox.Margin = '0,0,0,10'
    [void]$panel.Children.Add($userBox)

    $pwLbl = New-Object System.Windows.Controls.TextBlock
    $pwLbl.Text = 'Password'; $pwLbl.Margin = '0,0,0,3'
    [void]$panel.Children.Add($pwLbl)
    $inputGrid = New-Object System.Windows.Controls.Grid
    $pb = New-Object System.Windows.Controls.PasswordBox; $pb.Height = 28
    $tb = New-Object System.Windows.Controls.TextBox; $tb.Height = 28; $tb.VerticalContentAlignment = 'Center'
    $tb.Visibility = [System.Windows.Visibility]::Collapsed
    [void]$inputGrid.Children.Add($pb); [void]$inputGrid.Children.Add($tb)
    [void]$panel.Children.Add($inputGrid)

    $show = New-Object System.Windows.Controls.CheckBox
    $show.Content = 'Show password'; $show.Margin = '0,8,0,0'
    $show.Add_Checked({ $tb.Text = $pb.Password; $tb.Visibility = 'Visible'; $pb.Visibility = 'Collapsed'; $tb.Focus() | Out-Null })
    $show.Add_Unchecked({ $pb.Password = $tb.Text; $pb.Visibility = 'Visible'; $tb.Visibility = 'Collapsed'; $pb.Focus() | Out-Null })
    [void]$panel.Children.Add($show)

    $selOnly = New-Object System.Windows.Controls.CheckBox
    $selCount = @($ServerGrid.SelectedItems).Count
    $selOnly.Content = "Apply to selected rows only ($selCount selected) - otherwise ALL $($script:Servers.Count) row(s)"
    $selOnly.Margin = '0,10,0,0'
    $selOnly.IsEnabled = ($selCount -gt 0)
    [void]$panel.Children.Add($selOnly)

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,14,0,0'
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = 'Apply'; $ok.Width = 90; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Width = 80; $cancel.IsCancel = $true
    $ok.Add_Click({ $dlg.DialogResult = $true })
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($cancel)
    [void]$panel.Children.Add($btns)
    $dlg.Content = $panel
    $recorder = Enable-OneLinkWindowRecorder $dlg
    $userBox.Focus() | Out-Null

    if (-not $dlg.ShowDialog()) { return }

    $user = ([string]$userBox.Text).Trim()
    $plain = if ($show.IsChecked) { $tb.Text } else { $pb.Password }
    if ($user -eq '' -and [string]::IsNullOrEmpty($plain)) { Show-WarningMessage "Nothing entered - no changes made."; return }

    $targets = if ($selOnly.IsChecked -and $selCount -gt 0) { @($ServerGrid.SelectedItems) } else { @($script:Servers) }
    foreach ($s in $targets) {
        if ($user -ne '') { $s.Username = $user }
        if (-not [string]::IsNullOrEmpty($plain)) {
            $sec = New-Object System.Security.SecureString
            foreach ($ch in $plain.ToCharArray()) { $sec.AppendChar($ch) }
            $sec.MakeReadOnly()
            $s.SecurePassword = $sec
            $s.PasswordDisplay = ([string][char]0x25CF) * 6
        }
    }
    Invoke-GridRefresh $ServerGrid
    $what = @(); if ($user -ne '') { $what += 'username' }; if (-not [string]::IsNullOrEmpty($plain)) { $what += 'password' }
    Write-OneLinkLog "Applied shared $($what -join ' + ') to $($targets.Count) server row(s)." -Level Success
    Complete-OneLinkActivity -Name 'Set Shared Server Credentials' -Target (($targets | ForEach-Object { $_.Host }) -join ', ') -Context $recorder
    Show-InfoMessage "Applied the $($what -join ' and ') to $($targets.Count) server row(s)."
}

# Small modal with a checkbox per role in $script:OlRoles.
function Set-OlServerRoles {
    param([Parameter(Mandatory)][OlServer]$Server)

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Roles for $($Server.Host)"
    $dlg.Width = 320; $dlg.SizeToContent = 'Height'
    $dlg.WindowStartupLocation = 'CenterOwner'; $dlg.Owner = $script:Window; $dlg.ResizeMode = 'NoResize'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = '14'
    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = 'Mark this IP for one or more purposes:'
    $hdr.Margin = '0,0,0,8'
    [void]$panel.Children.Add($hdr)

    $current = $Server.RoleList()
    $checks = @{}
    foreach ($role in $script:OlRoles) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $role; $cb.Margin = '0,3,0,3'
        $cb.IsChecked = ($current -contains $role)
        $checks[$role] = $cb
        [void]$panel.Children.Add($cb)
    }

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,12,0,0'
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = 'OK'; $ok.Width = 80; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Width = 80; $cancel.IsCancel = $true
    $ok.Add_Click({ $dlg.DialogResult = $true })
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($cancel)
    [void]$panel.Children.Add($btns)
    $dlg.Content = $panel
    $recorder = Enable-OneLinkWindowRecorder $dlg

    if ($dlg.ShowDialog()) {
        $selected = @()
        foreach ($role in $script:OlRoles) { if ($checks[$role].IsChecked) { $selected += $role } }
        $Server.Roles = ($selected -join ', ')
        $Server.RolesDisplay = if ($selected.Count) { $Server.Roles } else { 'Select...' }
        Invoke-GridRefresh $ServerGrid
        Update-DbTargetCombo
        Complete-OneLinkActivity -Name 'Set Server Roles' -Target ([string]$Server.Host) -Context $recorder
    }
}

