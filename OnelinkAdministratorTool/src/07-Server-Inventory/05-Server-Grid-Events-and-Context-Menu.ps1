# Route the in-grid Password / Roles / Refresh / Resources button clicks to their actions.
$ServerGrid.AddHandler(
    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($eventSender, $e)
        $btn = $e.OriginalSource -as [System.Windows.Controls.Button]
        if ($null -eq $btn) { $btn = $e.Source -as [System.Windows.Controls.Button] }
        if ($null -eq $btn) { return }
        $row = $btn.DataContext -as [OlServer]
        if ($null -eq $row) { return }
        switch ([string]$btn.Tag) {
            'Password'        { Set-OlServerPassword -Server $row }
            'Roles'           { Set-OlServerRoles -Server $row }
            'RefreshServices' { Update-OneLinkServerServices -Server $row }
            'Resources'       { Show-OneLinkServerResources -Server $row }
            'Console'         { Show-OneLinkSshConsole -Server $row }
            'EditFile'        { Show-OneLinkFileEditor -Server $row }
        }
    }
)

# Right-click a server row -> per-server quick actions that target THAT server
# directly (no picker). A right-click first selects the row under the cursor.
$srvRowMenu = New-Object System.Windows.Controls.ContextMenu
$srvRowMenu.Add_PreviewMouseDown({ $script:ActClicks++; Register-OneLinkInteraction })
$srvRowMenu.Add_PreviewKeyDown({ Register-OneLinkInteraction })

# A greyed, non-clickable header line showing which server the menu acts on.
$miRowHeader = New-Object System.Windows.Controls.MenuItem
$miRowHeader.IsEnabled = $false
$miRowHeader.FontWeight = 'Bold'

$miRowConsole = New-Object System.Windows.Controls.MenuItem
$miRowConsole.Header = 'Command Console'
$miRowConsole.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -ne $row) { Show-OneLinkSshConsole -Server $row }
})

$miRowConnect = New-Object System.Windows.Controls.MenuItem
$miRowConnect.Header = 'Connect'
$miRowConnect.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    Complete-ServerGridEdits
    if ([string]::IsNullOrWhiteSpace($row.Host)) { Show-ErrorMessage 'This row has no IP / host.'; return }
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $metricStart = Get-Date
    Invoke-OneLinkConnectServer -Server $row
    Complete-OneLinkActivity -Name 'Connect Server' -Target ([string]$row.Host) -Outcome ($(if ($null -ne $row.Session) { 'Success' } else { 'Failed' })) -OperationSeconds (((Get-Date) - $metricStart).TotalSeconds)
    $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
    Invoke-GridRefresh $ServerGrid
    Update-ConnectionSummary; Update-TargetCombos; Update-DbTargetCombo; Update-ServiceChecklist
})

$miRowDisconnect = New-Object System.Windows.Controls.MenuItem
$miRowDisconnect.Header = 'Disconnect'
$miRowDisconnect.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    $metricStart = Get-Date; $metricOutcome = 'Success'
    if ($null -ne $row.Session) { try { Disconnect-OneLinkSsh -Session $row.Session } catch { $metricOutcome = 'Failed' } }
    $row.Session = $null; $row.Credential = $null
    $row.Status = 'Not connected'; $row.ServicesDisplay = '-'
    Reset-OneLinkServerHealth -Server $row
    Invoke-GridRefresh $ServerGrid
    Update-ConnectionSummary; Update-TargetCombos; Update-DbTargetCombo; Update-ServiceChecklist
    Complete-OneLinkActivity -Name 'Disconnect Server' -Target ([string]$row.Host) -Outcome $metricOutcome -OperationSeconds (((Get-Date) - $metricStart).TotalSeconds)
    Write-OneLinkLog "[$($row.Host)] Disconnected." -Level Info
})

$miRowReconnect = New-Object System.Windows.Controls.MenuItem
$miRowReconnect.Header = 'Reconnect'
$miRowReconnect.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    Complete-ServerGridEdits
    if ($null -ne $row.Session) { try { Disconnect-OneLinkSsh -Session $row.Session } catch { } }
    $row.Session = $null; $row.Credential = $null
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $metricStart = Get-Date
    Invoke-OneLinkConnectServer -Server $row
    Complete-OneLinkActivity -Name 'Reconnect Server' -Target ([string]$row.Host) -Outcome ($(if ($null -ne $row.Session) { 'Success' } else { 'Failed' })) -OperationSeconds (((Get-Date) - $metricStart).TotalSeconds)
    $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
    Invoke-GridRefresh $ServerGrid
    Update-ConnectionSummary; Update-TargetCombos; Update-DbTargetCombo; Update-ServiceChecklist
})

$miRowResources = New-Object System.Windows.Controls.MenuItem
$miRowResources.Header = 'View Resources'
$miRowResources.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -ne $row) { Show-OneLinkServerResources -Server $row }
})

$miRowCopyIp = New-Object System.Windows.Controls.MenuItem
$miRowCopyIp.Header = 'Copy IP'
$miRowCopyIp.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    try { [System.Windows.Clipboard]::SetText([string]$row.Host); Write-OneLinkLog "Copied IP $($row.Host) to the clipboard." -Level Info; Complete-OneLinkActivity -Name 'Copy Server IP' -Target ([string]$row.Host) } catch { Complete-OneLinkActivity -Name 'Copy Server IP' -Target ([string]$row.Host) -Outcome 'Failed' }
})

$miRowRemove = New-Object System.Windows.Controls.MenuItem
$miRowRemove.Header = 'Remove from list'
$miRowRemove.Add_Click({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    if ($null -ne $row.Session) { try { Disconnect-OneLinkSsh -Session $row.Session } catch { } }
    [void]$script:Servers.Remove($row)
    Complete-OneLinkActivity -Name 'Remove Server Row' -Target ([string]$row.Host)
    Invoke-GridRefresh $ServerGrid
    Update-TargetCombos; Update-DbTargetCombo; Update-ConnectionSummary; Update-ServiceChecklist
})

[void]$srvRowMenu.Items.Add($miRowHeader)
[void]$srvRowMenu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$srvRowMenu.Items.Add($miRowConsole)
[void]$srvRowMenu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$srvRowMenu.Items.Add($miRowConnect)
[void]$srvRowMenu.Items.Add($miRowDisconnect)
[void]$srvRowMenu.Items.Add($miRowReconnect)
[void]$srvRowMenu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$srvRowMenu.Items.Add($miRowResources)
[void]$srvRowMenu.Items.Add($miRowCopyIp)
[void]$srvRowMenu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$srvRowMenu.Items.Add($miRowRemove)

# Show the target server's IP in the header and enable only the items that apply.
$srvRowMenu.Add_Opened({
    $row = $ServerGrid.SelectedItem -as [OlServer]
    if ($null -eq $row) { return }
    $connected = ($null -ne $row.Session)
    $miRowHeader.Header      = [string]$row.Host
    $miRowConsole.IsEnabled  = $connected
    $miRowConnect.IsEnabled  = (-not $connected)
    $miRowDisconnect.IsEnabled = $connected
    $miRowReconnect.IsEnabled = $connected
    $miRowResources.IsEnabled = $connected
    $miRowCopyIp.IsEnabled   = (-not [string]::IsNullOrWhiteSpace($row.Host))
})
$ServerGrid.ContextMenu = $srvRowMenu

# Select the row under the cursor on right-click so the menu targets it.
$ServerGrid.Add_PreviewMouseRightButtonDown({
    param($eventSender, $e)
    $dep = $e.OriginalSource -as [System.Windows.DependencyObject]
    while ($null -ne $dep -and -not ($dep -is [System.Windows.Controls.DataGridRow])) {
        if ($dep -is [System.Windows.Media.Visual] -or $dep -is [System.Windows.Media.Media3D.Visual3D]) {
            $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
        }
        else {
            $dep = [System.Windows.LogicalTreeHelper]::GetParent($dep)
        }
    }
    if ($dep -is [System.Windows.Controls.DataGridRow]) { $ServerGrid.SelectedItem = $dep.Item }
    else { $ServerGrid.SelectedItem = $null }   # empty area -> menu suppressed below
})
# Don't show the menu when the right-click wasn't on a server row.
$ServerGrid.Add_ContextMenuOpening({
    param($eventSender, $e)
    if ($null -eq ($ServerGrid.SelectedItem -as [OlServer])) { $e.Handled = $true }
})

