# Return the servers that have a non-empty host, as strings.
function Get-OneLinkServerHosts {
    return @($script:Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Host) } | ForEach-Object { [string]$_.Host })
}

# Rebuild the generic "Target server" combos (Package, Services, SSL):
# "All servers" + every server host.
# ---- Multi-select target pickers -------------------------------------------
# Connected servers eligible for a picker (all connected; DB-marked only for 'Db').
function Get-OneLinkEligibleTargets {
    param([string]$Key)
    $connected = @($script:Servers | Where-Object { $null -ne $_.Session })
    if ($script:TargetPickers[$Key].DbOnly) {
        return @($connected | Where-Object { $_.HasRole('Database master') -or $_.HasRole('Database slave') })
    }
    return @($connected)
}

# Update a picker button's label from the ticks in its panel.
function Update-OneLinkTargetButton {
    param([string]$Key)
    $reg = $script:TargetPickers[$Key]
    $allChecked = $false; $hosts = @()
    foreach ($ch in $reg.Panel.Children) {
        if ($ch -is [System.Windows.Controls.CheckBox]) {
            if ([string]$ch.Tag -eq '__ALL__') { $allChecked = [bool]$ch.IsChecked }
            elseif ($ch.IsChecked) { $hosts += [string]$ch.Tag }
        }
    }
    if ($allChecked) { $reg.Button.Content = 'All servers' }
    elseif ($hosts.Count -eq 0) { $reg.Button.Content = $(if ($reg.DbOnly) { 'No DB server' } else { 'None selected' }) }
    elseif ($hosts.Count -eq 1) { $reg.Button.Content = $hosts[0] }
    else { $reg.Button.Content = "$($hosts.Count) servers" }
}

# The connected servers a picker currently targets: 'All' -> every eligible server;
# otherwise the individually-ticked hosts (empty array if none ticked).
function Get-OneLinkTargetHosts {
    param([string]$Key)
    $reg = $script:TargetPickers[$Key]
    $eligible = @(Get-OneLinkEligibleTargets -Key $Key)
    $allChecked = $false; $hosts = @()
    foreach ($ch in $reg.Panel.Children) {
        if ($ch -is [System.Windows.Controls.CheckBox]) {
            if ([string]$ch.Tag -eq '__ALL__') { $allChecked = [bool]$ch.IsChecked }
            elseif ($ch.IsChecked) { $hosts += [string]$ch.Tag }
        }
    }
    if ($allChecked) { return @($eligible) }
    return @($eligible | Where-Object { $hosts -contains [string]$_.Host })
}

# Rebuild a picker's checkbox panel from the eligible servers, preserving the prior
# selection. 'All servers' checkbox at the top; ticking a server clears All and vice
# versa. Programmatic IsChecked changes don't fire Click, so there is no re-entrancy.
function Update-OneLinkTargetPicker {
    param([string]$Key)
    $reg = $script:TargetPickers[$Key]
    $panel = $reg.Panel

    $priorAll = $false; $priorHosts = @(); $hadAny = $false
    foreach ($ch in $panel.Children) {
        if ($ch -is [System.Windows.Controls.CheckBox]) {
            $hadAny = $true
            if ([string]$ch.Tag -eq '__ALL__') { $priorAll = [bool]$ch.IsChecked }
            elseif ($ch.IsChecked) { $priorHosts += [string]$ch.Tag }
        }
    }
    if (-not $hadAny) { $priorAll = $true }   # first build -> default to All

    $panel.Children.Clear()
    $cbAll = New-Object System.Windows.Controls.CheckBox
    $cbAll.Content = 'All servers'; $cbAll.Tag = '__ALL__'; $cbAll.Margin = '0,2,0,4'; $cbAll.FontWeight = 'SemiBold'
    $cbAll.IsChecked = $priorAll
    [void]$panel.Children.Add($cbAll)

    foreach ($s in (Get-OneLinkEligibleTargets -Key $Key)) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = [string]$s.Host; $cb.Tag = [string]$s.Host; $cb.Margin = '0,2,0,2'
        $cb.IsChecked = ($priorHosts -contains [string]$s.Host)
        [void]$panel.Children.Add($cb)
    }

    $onChange = {
        param($sender, $e)
        if ([string]$sender.Tag -eq '__ALL__') {
            if ($sender.IsChecked) {
                foreach ($c in $panel.Children) { if ($c -is [System.Windows.Controls.CheckBox] -and [string]$c.Tag -ne '__ALL__') { $c.IsChecked = $false } }
            }
        }
        else {
            if ($sender.IsChecked) { $cbAll.IsChecked = $false }
        }
        Update-OneLinkTargetButton -Key $Key
        if ($Key -eq 'Service') { Update-ServiceChecklist }
        elseif ($Key -eq 'Db') { Update-OneLinkDbAllowedIp }
    }.GetNewClosure()
    foreach ($ch in $panel.Children) { if ($ch -is [System.Windows.Controls.CheckBox]) { $ch.Add_Click($onChange) } }

    Update-OneLinkTargetButton -Key $Key
}

# Rebuild the Service + Certificate target pickers (kept the old names so all the
# existing callers - connect / disconnect / add / remove / import - still work).
function Update-TargetCombos {
    Update-OneLinkTargetPicker -Key 'Service'
    Update-OneLinkTargetPicker -Key 'Cert'
}

# Rebuild the Database target picker (only 'Database master' / 'Database slave').
function Update-DbTargetCombo {
    Update-OneLinkTargetPicker -Key 'Db'
}

# Refresh the connection summary label and the Disconnect button state.
function Update-ConnectionSummary {
    $total = $script:Servers.Count
    $connected = @($script:Servers | Where-Object { $null -ne $_.Session }).Count

    if ($connected -gt 0) {
        $TxtConnectionStatus.Text = "$connected of $total server(s) connected"
        $TxtConnectionStatus.Foreground = [System.Windows.Media.Brushes]::ForestGreen
    }
    else {
        $TxtConnectionStatus.Text = if ($total -eq 0) { "No servers added" } else { "No servers connected" }
        $TxtConnectionStatus.Foreground = [System.Windows.Media.Brushes]::Crimson
    }

    $BtnDisconnect.IsEnabled = ($connected -gt 0)
}

# The systemd services a server runs, derived from its role marks.
function Get-OneLinkServerServices {
    param($Server)
    $list = @()
    foreach ($role in $Server.RoleList()) {
        if ($script:RoleServiceMap.Contains($role)) { $list += [string]$script:RoleServiceMap[$role] }
    }
    return @($list | Select-Object -Unique)
}

# Auto-discover NON-OneLink systemd service units on a server (for the 'Auxiliary
# Service' role). Lists installed unit-files whose state is enabled or disabled
# (i.e. real, manageable app services), excluding the onelink-* units that the
# existing OneLink logic already handles. Returns unit names without '.service'.
function Get-OneLinkAuxServices {
    param($Session)
    $cmd = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:`$PATH; " +
           "systemctl list-unit-files --type=service --no-legend 2>/dev/null | " +
           "awk '`$2==`"enabled`" || `$2==`"disabled`" {print `$1}' | " +
           "sed 's/\.service`$//' | grep -vi '^onelink' | sort -u"
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 30
    $names = @()
    if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
        $names = $r.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
    return @($names)
}

# Populate $Server.AuxServices if the server is marked 'Auxiliary Service' and they
# have not been discovered yet (or Force). No-op otherwise. Never throws.
function Update-OneLinkAuxServices {
    param($Server, [switch]$Force)
    if ($null -eq $Server -or $null -eq $Server.Session) { return }
    if (-not $Server.HasRole('Auxiliary Service')) { return }
    if (($null -ne $Server.AuxServices) -and (-not $Force)) { return }
    try { $Server.AuxServices = @(Get-OneLinkAuxServices -Session $Server.Session) }
    catch { $Server.AuxServices = @(); Write-OneLinkLog "[$($Server.Host)] Auxiliary service discovery failed: $($_.Exception.Message)" -Level Warning }
}

# The FULL set of services the Service Installer manages for a server: the OneLink
# role services (unchanged) PLUS any discovered auxiliary (non-OneLink) units when
# the server carries the 'Auxiliary Service' role. OneLink behaviour is untouched.
function Get-OneLinkServerManagedServices {
    param($Server)
    $list = @(Get-OneLinkServerServices $Server)
    if ($Server.HasRole('Auxiliary Service') -and $Server.AuxServices) {
        foreach ($s in @($Server.AuxServices)) { if ($list -notcontains $s) { $list += [string]$s } }
    }
    return @($list | Select-Object -Unique)
}

# True if $Unit is an auxiliary (non-OneLink) unit on $Server, so start/restart/stop
# must use plain systemctl instead of the nmenu (nstart/nstop) OneLink path.
function Test-OneLinkAuxService {
    param($Server, [string]$Unit)
    if ($null -eq $Server -or $null -eq $Server.AuxServices) { return $false }
    return (@($Server.AuxServices) -contains $Unit)
}

# Plain systemctl restart/stop for an auxiliary (non-OneLink) service. Success is
# judged by 'is-active' AFTER the action (like the OneLink helpers judge by state,
# not the exit code): Restart -> should be active; Stop -> should be inactive.
function Invoke-OneLinkPlainServiceAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][ValidateSet('Restart','Stop')][string]$Action
    )
    $u = ConvertTo-OneLinkBashArg ($Unit + '.service')
    $verb = if ($Action -eq 'Stop') { 'stop' } else { 'restart' }
    $cmd = "sudo systemctl $verb $u >/dev/null 2>&1; echo OLK_STATE=`$(systemctl is-active $u 2>/dev/null)"
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds)
    $t = (@($r.Output, $r.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    $state = if ($t -match 'OLK_STATE=(\S+)') { $Matches[1] } else { 'unknown' }
    if ($Action -eq 'Stop') {
        if ($state -eq 'inactive' -or $state -eq 'failed' -or $state -eq 'unknown') { return "stopped (state: $state)" }
        throw "still '$state' after stop."
    }
    if ($state -eq 'active') { return "restarted (active)" }
    throw "not active after restart (state: $state)."
}

# Rebuild the Services checklist for the currently-selected target: the UNION of
# services derived from the role marks of the target server(s). Each service is
# a checkbox (checked by default) so several can be actioned at once.
function Update-ServiceChecklist {
    # remember which were checked so a refresh keeps the user's ticks
    $previouslyChecked = @{}
    foreach ($child in $SvcCheckPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox]) {
            $previouslyChecked[[string]$child.Tag] = [bool]$child.IsChecked
        }
    }

    $SvcCheckPanel.Children.Clear()

    $targets = @(Get-OneLinkTargetHosts -Key 'Service')
    $services = New-Object System.Collections.Generic.List[string]
    foreach ($server in $targets) {
        Update-OneLinkAuxServices -Server $server   # discover non-OneLink units if marked Auxiliary and not yet done
        foreach ($svc in (Get-OneLinkServerManagedServices $server)) {
            if (-not $services.Contains($svc)) { $services.Add($svc) }
        }
    }

    if ($services.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = 'No services - connect a server and mark it (AppServer / Concentrator / ReportServer / nConnect / Auxiliary Service).'
        $tb.TextWrapping = 'Wrap'
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        [void]$SvcCheckPanel.Children.Add($tb)
        return
    }

    foreach ($svc in ($services | Sort-Object)) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $svc
        $cb.Tag = $svc
        $cb.Margin = '0,2,0,2'
        $cb.IsChecked = if ($previouslyChecked.ContainsKey($svc)) { $previouslyChecked[$svc] } else { $true }
        [void]$SvcCheckPanel.Children.Add($cb)
    }

    # Re-apply the current search filter so it survives a rebuild/refresh.
    Update-OneLinkServiceFilter
}

# Show only the service checkboxes whose name contains the search text (case-
# insensitive). Blank search shows all. Only affects visibility, not tick state.
function Update-OneLinkServiceFilter {
    if ($null -eq $TxtServiceSearch) { return }
    $q = ([string]$TxtServiceSearch.Text).Trim().ToLowerInvariant()
    foreach ($child in $SvcCheckPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox]) {
            $name = ([string]$child.Content).ToLowerInvariant()
            $child.Visibility = if ($q -eq '' -or $name.Contains($q)) { 'Visible' } else { 'Collapsed' }
        }
    }
}

# Tick / untick every service currently VISIBLE (i.e. matching the search filter).
function Set-OneLinkServicesChecked {
    param([bool]$Checked)
    foreach ($child in $SvcCheckPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.Visibility -eq 'Visible') {
            $child.IsChecked = $Checked
        }
    }
}

# The services the user has ticked in the checklist.
function Get-OneLinkCheckedServices {
    # Only services that are CHECKED and currently VISIBLE. The search filter hides
    # non-matching checkboxes (Visibility=Collapsed) without unticking them, so
    # without this a filtered-out but still-ticked service would be acted on too -
    # e.g. filtering to 'one', ticking onelink-appserver, but the default-ticked
    # hidden services still getting included. Visible-only matches what the user sees.
    $checked = @()
    foreach ($child in $SvcCheckPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked -and $child.Visibility -eq [System.Windows.Visibility]::Visible) {
            $checked += [string]$child.Tag
        }
    }
    return @($checked)
}

# Resolve the list of target servers for an operation, based on a combo value.
# Only currently-connected servers are returned.
function Get-TargetServers {
    param([string]$Selection)

    if ([string]::IsNullOrWhiteSpace($Selection) -or $Selection -eq 'All servers') {
        return @($script:Servers | Where-Object { $null -ne $_.Session })
    }

    return @($script:Servers | Where-Object { $_.Host -eq $Selection -and $null -ne $_.Session })
}

