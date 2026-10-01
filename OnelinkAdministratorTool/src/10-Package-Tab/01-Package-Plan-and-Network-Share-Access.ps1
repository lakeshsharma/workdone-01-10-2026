# ----------------------------------------------------------------------------
#  Package deployment (folder -> role-matched packages per server)
# ----------------------------------------------------------------------------

# Filename patterns that identify a package for each role. AppServer is the base
# 'onelink-<version>' package (the token after onelink- is a digit, i.e. NOT a
# role word), which is how it is told apart from the role-specific packages.
function Get-OlPackageRolePatterns {
    return @{
        'AppServer'    = '(?i)^onelink[-_]\d.*\.(rpm|deb)$'
        'Concentrator' = '(?i)^onelink[-_]concentrator[-_].*\.(rpm|deb)$'
        'ReportServer' = '(?i)^onelink[-_]report-server[-_].*\.(rpm|deb)$'
        'nConnect'     = '(?i)^onelink[-_]nconnect[-_].*\.(rpm|deb)$'
        # Matches both real filenames: onelink-webevents_15.4.1.6-1_amd64.deb (Debian,
        # underscore-separated) and onelink-webevents-15.4.1.6-1.x86_64.rpm (RPM).
        'WebEvents'    = '(?i)^onelink[-_]webevents[-_].*\.(rpm|deb)$'
    }
}

# Parse a comparable version out of a package filename (e.g. 15.4.1.258).
function Get-OlPackageVersion {
    param([string]$Name)
    if ($Name -match '(\d+(?:\.\d+){1,})') {
        try { return [version]$Matches[1] } catch { return [version]'0.0' }
    }
    return [version]'0.0'
}

# Pick the best package file for a role and OS: prefer the OS's extension
# (.rpm for redhat, .deb for debian) and the highest version. $Files entries are
# the {Name;Extension;Display} objects built by Build-OneLinkPackagePlan - Display
# is what gets returned (a plan-grid-friendly label), never a raw filesystem path.
function Select-OlPackageForRole {
    param($Files, [string]$Role, [string]$Os)

    $patterns = Get-OlPackageRolePatterns
    if (-not $patterns.ContainsKey($Role)) { return $null }
    $pat = $patterns[$Role]

    $roleMatches = @($Files | Where-Object { $_.Name -match $pat })
    if ($roleMatches.Count -eq 0) { return $null }

    # Only ever auto-pick a package built for THIS server's actual OS - an .rpm on a
    # Debian box (or a .deb on RHEL) won't install, so there is no safe "any extension"
    # fallback here. Previously this fell back to whatever extension WAS available,
    # which silently handed out a wrong-OS package instead of reporting no match. If
    # the OS wasn't detected (blank/unrecognized), don't guess - leave it unmatched so
    # the user picks manually from the (still-unfiltered) dropdown.
    $preferExt = switch ($Os) {
        'debian' { '.deb' }
        'redhat' { '.rpm' }
        default  { $null }
    }
    if (-not $preferExt) { return $null }

    $matchesForOs = @($roleMatches | Where-Object { $_.Extension.ToLowerInvariant() -eq $preferExt })
    if ($matchesForOs.Count -eq 0) { return $null }

    $best = $matchesForOs | Sort-Object @{ Expression = { Get-OlPackageVersion $_.Name } } -Descending | Select-Object -First 1
    return $best.Display
}

# Build the deployment plan: one row per (connected, role-marked server, role),
# with the matched package pre-selected. The Package cell is editable.
# Make a network (UNC) path reachable, optionally authenticating with the
# supplied user/password via `net use`. No-op for local paths or if already
# reachable. Credentials are optional (some shares need none).
# Quote one argument the way the Windows CommandLineToArgvW parser (used by
# net.exe) expects. This lets us pass a share name with spaces/'&' and a password
# with special characters WITHOUT going through a shell, so nothing is corrupted or
# injected (unlike 'cmd /c', where '&' would break the command).
function ConvertTo-OneLinkWinArg {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $e = [regex]::Replace($Value, '(\\*)"', '$1$1\"')   # escape any embedded quotes
    $e = [regex]::Replace($e, '(\\+)$', '$1$1')          # double trailing backslashes
    return '"' + $e + '"'
}

# Run net.exe via a real process pipe. Two reasons this is NOT a plain
# '& net.exe ... 2>&1':
#   1) A native command's stderr becomes a TERMINATING error under
#      $ErrorActionPreference='Stop' (which the app runs under) and used to crash
#      the tool ("The network connection could not be found").
#   2) MORE IMPORTANTLY, PowerShell's redirection SILENTLY DROPS net.exe's
#      "System error NNNN has occurred / <description>" text, so failures looked
#      like a blank "could not connect". A real StandardError pipe captures it.
# Arguments are quoted for CommandLineToArgvW (no shell), so special characters in
# the share name or password are safe. Never throws. Returns { Code; Output }.
function Invoke-OneLinkNetUse {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$NetArgs)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Join-Path $env:SystemRoot 'System32\net.exe')
        $psi.Arguments = (($NetArgs | ForEach-Object { ConvertTo-OneLinkWinArg $_ }) -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEnd()
        $err = $proc.StandardError.ReadToEnd()
        if (-not $proc.WaitForExit(60000)) {
            try { $proc.Kill() } catch { }
            return [pscustomobject]@{ Code = 1; Output = 'The network command timed out (the server did not respond).' }
        }
        $txt = (($out + "`n" + $err) -replace "`r", '').Trim()
        return [pscustomobject]@{ Code = $proc.ExitCode; Output = $txt }
    }
    catch { return [pscustomobject]@{ Code = 1; Output = $_.Exception.Message } }
}

function Connect-OneLinkNetworkPath {
    param([string]$Path, [string]$User, [string]$Password)
    if ($Path -notmatch '^\\\\') { return }                       # not a UNC path
    if (Test-Path -LiteralPath $Path) { return }                  # already reachable
    $root = if ($Path -match '^(\\\\[^\\]+\\[^\\]+)') { $matches[1] } else { $Path }
    if ([string]::IsNullOrWhiteSpace($User)) {
        Invoke-OneLinkNetUse use "$root" | Out-Null
    }
    else {
        Invoke-OneLinkNetUse use "$root" "$Password" "/user:$User" | Out-Null
        Write-OneLinkLog "Connected to network share $root as $User." -Level Info
    }
}

# Test whether a network (UNC) path can be REACHED. It checks access first - which
# is what actually matters and often needs no explicit login at all, because the
# path already opens with the user's current Windows sign-in / cached credentials
# (very common for domain and DFS paths like \\domain\namespace\...). Only if the
# path is NOT already reachable does it fall back to an explicit 'net use' with the
# supplied credentials, surfacing the real Windows error if that fails.
# Returns { Ok; Message }.
function Test-OneLinkNetworkLogin {
    param([string]$Path, [string]$User, [string]$Password)
    $p = ([string]$Path).Trim()
    if ($p -notmatch '^\\\\') { return [pscustomobject]@{ Ok = $false; Message = "This test is only for network paths (\\server\share\...).`n`nThe path above is not a network path." } }
    $root = if ($p -match '^(\\\\[^\\]+\\[^\\]+)') { $matches[1] } else { $p }

    # 1) Access test (the important one). If the path already opens, we are done -
    #    no login is needed, whatever is in the User/Password boxes.
    if (Test-Path -LiteralPath $p) {
        return [pscustomobject]@{ Ok = $true; Message = "ACCESS OK.`n`nThis location already opens with your current Windows sign-in - no separate Network login is needed:`n$p`n`nTip: leave the 'Network login' box UNTICKED for this share." }
    }

    # 2) Not reachable as-is. If no credentials were given, say so plainly.
    if ([string]::IsNullOrWhiteSpace($User)) {
        return [pscustomobject]@{ Ok = $false; Message = "NOT reachable with your current Windows sign-in:`n$p`n`nEnter a User and Password and test again to try an explicit login, or check the path / VPN / permissions." }
    }

    # 3) Try an explicit login with the supplied credentials.
    Invoke-OneLinkNetUse use "$root" /delete /y | Out-Null   # drop any stale handle first (ignored if none)
    $r = Invoke-OneLinkNetUse use "$root" "$Password" "/user:$User"
    if ($r.Code -eq 0 -and (Test-Path -LiteralPath $p)) {
        return [pscustomobject]@{ Ok = $true; Message = "LOGIN OK.`n`nConnected to  $root`nas user       $User`n`nPath now reachable: $p" }
    }
    Invoke-OneLinkNetUse use "$root" /delete /y | Out-Null    # don't leave a half-open handle

    $detail = $r.Output
    $srvName = ($root -replace '^\\\\', '') -split '\\' | Select-Object -First 1
    $hint = ''
    switch -Regex ($detail) {
        'System error 1219'                 { $hint = "You already have a connection to \\$srvName using different credentials, and Windows allows only ONE set per server. Untick 'Network login' to use your current sign-in, or run  net use * /delete  in a command prompt and retry." ; break }
        'System error (86|1326|1327)'       { $hint = "The username or password was rejected. For a domain share, try the DOMAIN\user form (or user@domain) and re-check the password." ; break }
        'System error (53|67|2250|1231)'    { $hint = "The server or share name was not found. A domain/DFS path (\\$srvName\...) needs domain connectivity - check VPN and the exact share name." ; break }
        'System error 5|Access is denied'   { $hint = "Access is denied: the account signed in but is not permitted on this share." ; break }
    }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "Windows could not connect (no details returned by net use)." }
    $msg = "LOGIN FAILED for  $root  as $User.`n`n$detail"
    if ($hint) { $msg += "`n`n$hint" }
    return [pscustomobject]@{ Ok = $false; Message = $msg }
}

$BtnPkgNetTest.Add_Click({
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $res = Test-OneLinkNetworkLogin -Path $TxtPackagePath.Text -User $TxtNetUser.Text -Password $PwdNetPass.Password
        if ($res.Ok) { Write-OneLinkLog $res.Message.Replace([Environment]::NewLine, ' ') -Level Success; Show-InfoMessage $res.Message }
        else { Write-OneLinkLog $res.Message.Replace([Environment]::NewLine, ' ') -Level Warning; Show-WarningMessage $res.Message }
    }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
})

# Human-readable byte size (e.g. 245.3 MB) for the plan grid's artifact-size column.
function Format-OneLinkSize {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return "$Bytes B" }
    $u = 'KB', 'MB', 'GB', 'TB'; $i = -1; $v = [double]$Bytes
    do { $v = $v / 1024; $i++ } while ($v -ge 1024 -and $i -lt ($u.Count - 1))
    return ('{0:0.0} {1}' -f $v, $u[$i])
}

# Resolves a plan row's Package DISPLAY string (a relative path, or "[Folder] rel\path"
# when more than one root folder was scanned) back to its real full path on disk.
# $script:PackagePathLookup is rebuilt on every Build-OneLinkPackagePlan.
function Resolve-OneLinkPackagePath {
    param([string]$Folder, [string]$Display)
    if ($script:PackagePathLookup -and $script:PackagePathLookup.ContainsKey($Display)) { return $script:PackagePathLookup[$Display] }
    return (Join-Path $Folder $Display)   # fallback for a legacy/simple single-folder value
}

# Size text for a package file already in the plan ('' for '(skip)' / missing).
function Get-OneLinkPackageSizeText {
    param([string]$Folder, [string]$Display)
    if ([string]::IsNullOrWhiteSpace($Display) -or $Display -eq '(skip)') { return '' }
    try {
        $fp = Resolve-OneLinkPackagePath -Folder $Folder -Display $Display
        if (Test-Path -LiteralPath $fp -PathType Leaf) { return (Format-OneLinkSize -Bytes ((Get-Item -LiteralPath $fp).Length)) }
    }
    catch { }
    return ''
}

# Recursively scan one root folder for .rpm/.deb files, tagging each with a plan-grid
# DISPLAY string (its path relative to THIS root, prefixed with the root's own folder
# name when more than one root is in play so same-named files in different folders
# never collide) and recording the real full path in $script:PackagePathLookup.
function Get-OneLinkPackageFilesUnder {
    param([string]$Root, [bool]$MultiRoot)
    $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd([char[]]('\', '/'))
    $rootLabel = Split-Path -Path $rootFull -Leaf
    $out = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '(?i)\.(rpm|deb)$' } |
        ForEach-Object {
            $rel = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]('\', '/'))
            $display = if ($MultiRoot) { "[$rootLabel] $rel" } else { $rel }
            if ($script:PackagePathLookup.ContainsKey($display) -and $script:PackagePathLookup[$display] -ne $_.FullName) {
                # Same display string from two different files (rare) - disambiguate.
                $display = "$display (#$([Math]::Abs($_.FullName.GetHashCode()) % 1000))"
            }
            $script:PackagePathLookup[$display] = $_.FullName
            $out.Add([pscustomobject]@{ Name = $_.Name; Extension = $_.Extension; Display = $display })
        }
    return $out
}

# A local-folder picker that supports selecting SEVERAL folders (any drive, any
# branch) in one dialog session - standard .NET has no built-in multi-select folder
# dialog. Explorer-style navigator: one list of the CURRENT folder's subfolders,
# double-click to open one, Ctrl+click / Shift+click to multi-select several (native
# ListBox behaviour), search-as-you-type to filter the current folder, quick-place
# shortcuts (generic labels only - never a literal username in the UI), and a running
# "Added folders" list with Remove Selected / Remove All. One primary action button
# (next to Cancel) both adds the current pick and - once nothing is highlighted -
# finishes and closes, so there's no separate/confusing OK button. Starts at "This
# PC" (the drive list). Returns a string[] of every folder added, or $null if
# cancelled. No new assembly/module - plain WPF (incl. XamlReader for two small,
# reused style/template fragments) + System.IO.
#
# NOTE ON HELPERS: every reusable piece below (icon, chip, styled button, add-path)
# is a SCRIPTBLOCK VARIABLE, not a nested 'function'. .GetNewClosure() only snapshots
# VARIABLES from the enclosing scope - a nested 'function' is never visible from
# inside a closure (confirmed: even a function calling itself through a
# GetNewClosure()'d event handler can't resolve its own name). Every helper here is
# therefore defined - in dependency order - BEFORE anything that captures it via
# GetNewClosure(), exactly like $refreshSummary/$navigateTo already did elsewhere.
function Show-OneLinkMultiFolderPicker {
    param([string[]]$InitialSelection = @())

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($p in $InitialSelection) { if ($p -and -not ($selected -contains $p)) { [void]$selected.Add($p) } }
    $state = @{ Path = ''; AllItems = @(); Suppress = $false }   # Path '' = "This PC" (the drive list)

    # One rounded-corner look shared by every button in this dialog (colors differ per
    # button via Background/Foreground/BorderBrush; the chrome - corners, hover/press/
    # disabled dimming - is defined once and reused) and one shared look for every list
    # row (folder rows and "Added folders" rows alike): hover tint, a distinct selected
    # tint, dimmed/italic for placeholder rows. Built via XamlReader.Parse - still plain
    # WPF, nothing new to ship.
    $btnTemplate = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
  <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
    </Trigger>
    <Trigger Property="IsPressed" Value="True">
      <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
    </Trigger>
    <Trigger Property="IsEnabled" Value="False">
      <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
'@)
    $itemStyle = [System.Windows.Markup.XamlReader]::Parse(@'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ListBoxItem">
  <Setter Property="Padding" Value="8,6"/>
  <Setter Property="Margin" Value="2,1"/>
  <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ListBoxItem">
        <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
          <ContentPresenter/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="#EEF2FF"/>
          </Trigger>
          <Trigger Property="IsSelected" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="#C7D2FE"/>
          </Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@)

    # A tiny two-rectangle folder glyph drawn with plain Shapes (no icon font / image
    # asset, so nothing to embed or mis-encode). Color varies by row type (amber for a
    # real folder, blue for a drive, green for an already-added row, gray when disabled).
    $NewFolderIcon = {
        param([string]$FillHex = '#F6B93B')
        $canvas = New-Object System.Windows.Controls.Canvas
        $canvas.Width = 16; $canvas.Height = 13; $canvas.Margin = '0,0,8,0'; $canvas.VerticalAlignment = 'Center'
        $tab = New-Object System.Windows.Shapes.Rectangle
        $tab.Width = 7; $tab.Height = 3; $tab.Fill = $FillHex; $tab.RadiusX = 1; $tab.RadiusY = 1
        [System.Windows.Controls.Canvas]::SetLeft($tab, 0); [System.Windows.Controls.Canvas]::SetTop($tab, 0)
        $body = New-Object System.Windows.Shapes.Rectangle
        $body.Width = 16; $body.Height = 11; $body.Fill = $FillHex; $body.RadiusX = 2; $body.RadiusY = 2
        [System.Windows.Controls.Canvas]::SetLeft($body, 0); [System.Windows.Controls.Canvas]::SetTop($body, 2)
        [void]$canvas.Children.Add($tab); [void]$canvas.Children.Add($body)
        return $canvas
    }.GetNewClosure()

    # One row (folder, drive, placeholder, or an "Added folders" entry). NameText is
    # stashed as a PowerShell note property (ETS) so the search filter can read the
    # plain name back out without digging through the visual tree.
    $NewListChip = {
        param([string]$Name, [string]$Tag, [bool]$Enabled = $true, [string]$IconColor = '#F6B93B', [string]$SubText = '')
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Tag = $Tag; $li.IsEnabled = $Enabled; $li.Style = $itemStyle
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'
        [void]$sp.Children.Add((& $NewFolderIcon -FillHex $(if ($Enabled) { $IconColor } else { '#CBD5E1' })))
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Name; $tb.VerticalAlignment = 'Center'; $tb.FontSize = 13
        if (-not $Enabled) { $tb.Foreground = '#94A3B8'; $tb.FontStyle = 'Italic' }
        [void]$sp.Children.Add($tb)
        if ($SubText) {
            $sub = New-Object System.Windows.Controls.TextBlock
            $sub.Text = "   $SubText"; $sub.VerticalAlignment = 'Center'; $sub.FontSize = 11; $sub.Foreground = '#94A3B8'
            [void]$sp.Children.Add($sub)
        }
        $li.Content = $sp
        $li | Add-Member -NotePropertyName NameText -NotePropertyValue $Name -Force
        return $li
    }.GetNewClosure()

    $NewStyledButton = {
        param([string]$Text, [string]$Bg, [string]$Fg, [string]$Border = $Bg)
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $Text; $b.Template = $btnTemplate
        $b.Background = $Bg; $b.Foreground = $Fg; $b.BorderBrush = $Border; $b.BorderThickness = '1'
        $b.Padding = '14,7'; $b.Margin = '0,0,8,0'; $b.Cursor = 'Hand'; $b.FontWeight = 'SemiBold'
        return $b
    }.GetNewClosure()

    $AddPath = { param([string]$p) if ($p -and -not ($selected -contains $p)) { [void]$selected.Add($p) } }.GetNewClosure()

    $win = New-Object System.Windows.Window
    $win.Title = 'Select one or more folders'
    $win.Width = 660; $win.Height = 720
    $win.WindowStartupLocation = 'CenterOwner'; $win.ResizeMode = 'CanResize'
    $win.Background = '#F8FAFC'
    if ($script:Window) { $win.Owner = $script:Window }

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = '14'
    foreach ($h in 'Auto', 'Auto', 'Auto', '*', 'Auto', 'Auto', 'Auto') {
        $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $h
        [void]$grid.RowDefinitions.Add($rd)
    }

    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Double-click a folder to open it. Ctrl+click or Shift+click to select several at once. Type to search the current folder. Repeat from anywhere, then finish below."
    $hint.TextWrapping = 'Wrap'; $hint.Margin = '0,0,0,10'; $hint.Foreground = '#334155'
    [System.Windows.Controls.Grid]::SetRow($hint, 0)
    [void]$grid.Children.Add($hint)

    # Quick places row: the "Quick places:" label goes in now; the shortcut buttons
    # themselves are appended later (after $navigateTo exists below) so their Click
    # handlers close over the REAL $navigateTo instead of one that doesn't exist yet.
    # GENERIC labels only - no literal path/username ever shown in the label itself.
    $quickRow = New-Object System.Windows.Controls.WrapPanel
    $quickRow.Margin = '0,0,0,10'
    $quickLabel = New-Object System.Windows.Controls.TextBlock
    $quickLabel.Text = 'Quick places:'; $quickLabel.VerticalAlignment = 'Center'; $quickLabel.Margin = '0,0,8,4'
    $quickLabel.Foreground = '#64748B'; $quickLabel.FontSize = 12
    [void]$quickRow.Children.Add($quickLabel)
    [System.Windows.Controls.Grid]::SetRow($quickRow, 1)
    [void]$grid.Children.Add($quickRow)

    # Nav row: Up + a combined address/search box (a full path + Enter/Go jumps there;
    # a few letters live-filters the CURRENT folder's list, case-insensitive).
    $nav = New-Object System.Windows.Controls.Grid
    $nav.Margin = '0,0,0,8'
    foreach ($w in 'Auto', '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w
        [void]$nav.ColumnDefinitions.Add($cd)
    }
    $upBtn = & $NewStyledButton -Text 'Up' -Bg '#F1F5F9' -Fg '#334155' -Border '#CBD5E1'
    $upBtn.Width = 55
    [System.Windows.Controls.Grid]::SetColumn($upBtn, 0)
    [void]$nav.Children.Add($upBtn)
    $pathBox = New-Object System.Windows.Controls.TextBox
    $pathBox.Margin = '0,0,8,0'; $pathBox.VerticalContentAlignment = 'Center'; $pathBox.Padding = '6,4'; $pathBox.BorderBrush = '#CBD5E1'
    [System.Windows.Controls.Grid]::SetColumn($pathBox, 1)
    [void]$nav.Children.Add($pathBox)
    $goBtn = & $NewStyledButton -Text 'Go' -Bg '#2563EB' -Fg 'White'
    $goBtn.Width = 64; $goBtn.Margin = '0'
    [System.Windows.Controls.Grid]::SetColumn($goBtn, 2)
    [void]$nav.Children.Add($goBtn)
    [System.Windows.Controls.Grid]::SetRow($nav, 2)
    [void]$grid.Children.Add($nav)

    $lb = New-Object System.Windows.Controls.ListBox
    $lb.SelectionMode = 'Extended'; $lb.BorderBrush = '#E2E8F0'; $lb.Background = 'White'
    [System.Windows.Controls.Grid]::SetRow($lb, 3)
    [void]$grid.Children.Add($lb)

    $addedLabel = New-Object System.Windows.Controls.TextBlock
    $addedLabel.Margin = '0,10,0,4'; $addedLabel.Foreground = '#334155'; $addedLabel.FontWeight = 'SemiBold'
    [System.Windows.Controls.Grid]::SetRow($addedLabel, 4)
    [void]$grid.Children.Add($addedLabel)

    $lbAdded = New-Object System.Windows.Controls.ListBox
    $lbAdded.SelectionMode = 'Extended'; $lbAdded.Height = 100; $lbAdded.BorderBrush = '#E2E8F0'; $lbAdded.Background = 'White'
    [System.Windows.Controls.Grid]::SetRow($lbAdded, 5)
    [void]$grid.Children.Add($lbAdded)

    $mainBtn = & $NewStyledButton -Text 'Add Selected' -Bg '#2563EB' -Fg 'White'
    $mainBtn.MinWidth = 130; $mainBtn.IsDefault = $true

    $removeSelBtn = & $NewStyledButton -Text 'Remove Selected' -Bg '#FEF3C7' -Fg '#92400E' -Border '#FCD34D'
    $removeAllBtn = & $NewStyledButton -Text 'Remove All' -Bg '#DC2626' -Fg 'White'
    $cancelBtn = & $NewStyledButton -Text 'Cancel' -Bg '#F1F5F9' -Fg '#334155' -Border '#CBD5E1'
    $cancelBtn.IsCancel = $true; $cancelBtn.Margin = '0'

    $actionRow = New-Object System.Windows.Controls.Grid
    $actionRow.Margin = '0,10,0,0'
    foreach ($w in 'Auto', '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w
        [void]$actionRow.ColumnDefinitions.Add($cd)
    }
    $leftPanel = New-Object System.Windows.Controls.StackPanel
    $leftPanel.Orientation = 'Horizontal'
    [void]$leftPanel.Children.Add($removeSelBtn); [void]$leftPanel.Children.Add($removeAllBtn)
    [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)
    [void]$actionRow.Children.Add($leftPanel)
    $rightPanel = New-Object System.Windows.Controls.StackPanel
    $rightPanel.Orientation = 'Horizontal'; $rightPanel.HorizontalAlignment = 'Right'
    [void]$rightPanel.Children.Add($mainBtn); [void]$rightPanel.Children.Add($cancelBtn)
    [System.Windows.Controls.Grid]::SetColumn($rightPanel, 2)
    [void]$actionRow.Children.Add($rightPanel)
    [System.Windows.Controls.Grid]::SetRow($actionRow, 6)
    [void]$grid.Children.Add($actionRow)

    # ---- From here on: closures, defined in dependency order, then wired up. ----

    $refreshAdded = {
        $addedLabel.Text = if ($selected.Count -eq 0) { 'Added folders: (none yet)' } else { "Added folders ($($selected.Count)):" }
        $lbAdded.Items.Clear()
        foreach ($p in $selected) {
            $leaf = Split-Path -Path $p -Leaf
            if ([string]::IsNullOrEmpty($leaf)) { $leaf = $p }
            [void]$lbAdded.Items.Add((& $NewListChip -Name $leaf -Tag $p -IconColor '#34D399' -SubText $p))
        }
    }.GetNewClosure()

    $updateMainBtnLabel = {
        if ($lb.SelectedItems.Count -gt 0) { $mainBtn.Content = 'Add Selected' }
        else { $mainBtn.Content = if ($selected.Count -gt 0) { "Done ($($selected.Count) added)" } else { 'Done' } }
    }.GetNewClosure()

    # Populates $lb for $state.Path: '' lists drives ("This PC"); otherwise the
    # subfolders of that path. A folder that can't be read just shows an explanatory
    # placeholder row - it never blocks navigating anywhere else. Also snapshots the
    # unfiltered row list into $state.AllItems for the search box to filter against.
    $navigateTo = {
        param([string]$NewPath)
        try {
            $state.Path = $NewPath
            $state.Suppress = $true
            $lb.Items.Clear()
            if ([string]::IsNullOrEmpty($NewPath)) {
                $pathBox.Text = 'This PC'
                $upBtn.IsEnabled = $false
                try { $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }) } catch { $drives = @() }
                foreach ($d in $drives) {
                    $label = if ($d.VolumeLabel) { "$($d.Name)  ($($d.VolumeLabel))" } else { [string]$d.Name }
                    [void]$lb.Items.Add((& $NewListChip -Name $label -Tag $d.RootDirectory.FullName -IconColor '#60A5FA'))
                }
            }
            else {
                $pathBox.Text = $NewPath
                $upBtn.IsEnabled = $true
                $gciErr = $null
                $subs = @(Get-ChildItem -LiteralPath $NewPath -Directory -ErrorAction SilentlyContinue -ErrorVariable gciErr | Sort-Object Name)
                foreach ($d in $subs) { [void]$lb.Items.Add((& $NewListChip -Name $d.Name -Tag $d.FullName -IconColor '#F6B93B')) }
                if ($subs.Count -eq 0) {
                    $msg = if ($gciErr -and $gciErr.Count -gt 0) { '(cannot read this folder)' } else { '(no subfolders)' }
                    [void]$lb.Items.Add((& $NewListChip -Name $msg -Tag '' -Enabled $false))
                }
            }
            $state.AllItems = @($lb.Items)
            & $updateMainBtnLabel
        }
        catch { }
        finally { $state.Suppress = $false }
    }.GetNewClosure()

    $upBtn.Add_Click({
        try {
            if ([string]::IsNullOrEmpty($state.Path)) { return }
            $parent = Split-Path -Path $state.Path -Parent
            & $navigateTo ([string]$parent)
        }
        catch { & $navigateTo '' }
    }.GetNewClosure())

    $goToTyped = {
        try {
            $p = $pathBox.Text.Trim().Trim('"')
            if ($p -eq '' -or $p -eq 'This PC') { & $navigateTo ''; return }
            if (Test-Path -LiteralPath $p -PathType Container) { & $navigateTo $p; return }
            # Not a literal path - if the live filter below has narrowed the CURRENT
            # folder down to exactly one match, Enter/Go opens it directly.
            $shown = @($lb.Items | Where-Object { $_.IsEnabled -and -not [string]::IsNullOrEmpty([string]$_.Tag) })
            if ($shown.Count -eq 1) { & $navigateTo ([string]$shown[0].Tag); return }
            if ($shown.Count -gt 1) { return }   # several matches already shown - nothing more to do here
            Show-WarningMessage "No folder found here matching '$p'."
        }
        catch { }
    }.GetNewClosure()
    $goBtn.Add_Click($goToTyped)
    $pathBox.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { & $goToTyped }
    }.GetNewClosure())

    # Live, case-insensitive search-as-you-type within the CURRENT folder's list (a
    # full path is left alone here - Enter/Go above handles jumping to one).
    $pathBox.Add_TextChanged({
        if ($state.Suppress) { return }
        try {
            $q = $pathBox.Text
            if ([string]::IsNullOrEmpty($q) -or $q -match '^[A-Za-z]:\\' -or $q.StartsWith('\\')) {
                $lb.Items.Clear(); foreach ($it in $state.AllItems) { [void]$lb.Items.Add($it) }
                return
            }
            $lb.Items.Clear()
            $ql = $q.ToLowerInvariant()
            $found = @($state.AllItems | Where-Object { $_.NameText -and ([string]$_.NameText).ToLowerInvariant().Contains($ql) })
            if ($found.Count -eq 0) { [void]$lb.Items.Add((& $NewListChip -Name "No folder here matches '$q'" -Tag '' -Enabled $false)) }
            else { foreach ($m in $found) { [void]$lb.Items.Add($m) } }
        }
        catch { }
    }.GetNewClosure())

    $lb.Add_MouseDoubleClick({
        try {
            $it = $lb.SelectedItem
            if ($null -eq $it -or -not $it.IsEnabled -or [string]::IsNullOrEmpty([string]$it.Tag)) { return }
            & $navigateTo ([string]$it.Tag)
        }
        catch { }
    }.GetNewClosure())

    $lb.Add_SelectionChanged({ & $updateMainBtnLabel }.GetNewClosure())

    $removeSelBtn.Add_Click({
        try {
            $tags = @($lbAdded.SelectedItems | ForEach-Object { [string]$_.Tag })
            foreach ($t in $tags) { [void]$selected.Remove($t) }
            & $refreshAdded
            & $updateMainBtnLabel
        }
        catch { }
    }.GetNewClosure())

    $removeAllBtn.Add_Click({
        try {
            $selected.Clear()
            & $refreshAdded
            & $updateMainBtnLabel
        }
        catch { }
    }.GetNewClosure())

    # The one primary action button: adds whatever is currently highlighted in the
    # browse list (dialog stays open - navigate elsewhere and add more); once nothing
    # is highlighted, the same button finishes and closes. No separate/redundant OK.
    $mainBtn.Add_Click({
        try {
            if ($lb.SelectedItems.Count -gt 0) {
                foreach ($it in @($lb.SelectedItems)) {
                    if ($it.IsEnabled -and -not [string]::IsNullOrEmpty([string]$it.Tag)) { & $AddPath ([string]$it.Tag) }
                }
                $lb.SelectedItems.Clear()
                & $refreshAdded
                & $updateMainBtnLabel
            }
            else {
                $win.DialogResult = $true
            }
        }
        catch { try { $win.Close() } catch { } }
    }.GetNewClosure())

    # Now that $navigateTo exists, build the quick-place shortcut buttons and append
    # them to the row created earlier. GENERIC labels only (This PC / Desktop /
    # Documents / Downloads) - the real resolved path only appears in the address bar
    # AFTER navigating there, same as it would from typing or double-clicking in.
    $places = [ordered]@{
        'This PC'   = { '' }
        'Desktop'   = { [Environment]::GetFolderPath('Desktop') }
        'Documents' = { [Environment]::GetFolderPath('MyDocuments') }
        'Downloads' = { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
    }
    foreach ($label in $places.Keys) {
        $target = $places[$label]
        $chip = & $NewStyledButton -Text $label -Bg '#EEF2FF' -Fg '#3730A3' -Border '#C7D2FE'
        $chip.Margin = '0,0,8,4'
        $chip.Add_Click({ try { & $navigateTo ([string](& $target)) } catch { } }.GetNewClosure())
        [void]$quickRow.Children.Add($chip)
    }

    & $refreshAdded
    & $navigateTo ''   # start at "This PC"

    $win.Content = $grid
    if ($win.ShowDialog()) { return , @($selected.ToArray()) }
    return $null
}

function Build-OneLinkPackagePlan {
    # The Folder box holds either ONE path (local or network, typed or picked) or
    # SEVERAL local paths chosen in one go via the multi-select Browse picker, shown
    # joined with ' ; '. Splitting on ';' keeps the common single-path case byte-for-
    # byte identical to before (a plain path has no ';' in it, so this is a no-op split).
    $roots = @(([string]$TxtPackagePath.Text) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique)
    if ($roots.Count -eq 0) {
        Show-ErrorMessage "Select at least one package folder (Browse...)."
        return
    }

    # Network auth applies ONLY when there's a single path - exactly the original,
    # unchanged behaviour. Multiple paths only ever come from the LOCAL multi-select
    # Browse dialog, so network login never applies once there's more than one.
    if ($roots.Count -eq 1) {
        $pkgNetUser = if ($ChkPkgNetAuth.IsChecked) { $TxtNetUser.Text } else { '' }
        $pkgNetPass = if ($ChkPkgNetAuth.IsChecked) { $PwdNetPass.Password } else { '' }
        Connect-OneLinkNetworkPath -Path $roots[0] -User $pkgNetUser -Password $pkgNetPass
    }
    else {
        foreach ($p in $roots) {
            if ($p -match '^\\\\') { Show-ErrorMessage "Multiple folders are selected, but '$p' looks like a network path. The multi-select Browse picker only offers LOCAL folders - use a single network path on its own (no ';') instead."; return }
        }
    }

    $multiRoot = $roots.Count -gt 1

    $script:PackagePathLookup = @{}
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Show-ErrorMessage "Folder not found or not reachable: $root`n`nIf this is a network path, check the path and the user/password."
            return
        }
        foreach ($f in (Get-OneLinkPackageFilesUnder -Root $root -MultiRoot $multiRoot)) { $files.Add($f) }
    }
    # NOT '@($files)': on this PS runtime, wrapping a System.Collections.Generic.List[object]
    # directly in @(...) throws "Argument types do not match" (reproducible even on an EMPTY
    # list - a runtime/reflection quirk, not a data problem). .ToArray() is the same result,
    # unambiguously.
    $files = $files.ToArray()
    if ($files.Count -eq 0) {
        $where = if ($roots.Count -gt 1) { "any of the $($roots.Count) selected folders (including subfolders)" } else { "$($roots[0]) (including subfolders)" }
        Show-ErrorMessage "No .rpm or .deb packages found in $where."
        return
    }

    $connected = @($script:Servers | Where-Object { $null -ne $_.Session })
    if ($connected.Count -eq 0) { Show-ErrorMessage "Connect at least one server before building the plan."; return }

    $availableList = @(@($files | ForEach-Object { $_.Display } | Sort-Object) + '(skip)')
    # DB roles have no package. 'Auxiliary Service' IS a package role but has no
    # filename pattern (it's any non-OneLink app), so the user picks the file.
    $packageRoles = @('AppServer','Concentrator','ReportServer','nConnect','WebEvents','Auxiliary Service')

    # $folder (single) is kept only as the legacy fallback inside Get-OneLinkPackageSizeText
    # / Resolve-OneLinkPackagePath when a Display string isn't in the lookup for some reason.
    $folder = $roots[0]

    $script:PackagePlan.Clear()
    $rowCount = 0
    foreach ($server in $connected) {
        foreach ($role in $server.RoleList()) {
            if ($packageRoles -notcontains $role) { continue }   # DB roles skipped
            $best = Select-OlPackageForRole -Files $files -Role $role -Os ([string]$server.Os)
            $row = [OlPlanRow]::new()
            $row.Host = [string]$server.Host
            $row.Role = $role
            $row.Server = $server
            $row.Available = $availableList
            if ($best) { $row.Package = $best; $row.Status = 'Planned' }
            elseif ($role -eq 'Auxiliary Service') { $row.Package = '(skip)'; $row.Status = 'Pick a package' }
            else { $row.Package = '(skip)'; $row.Status = 'No matching package' }
            $row.Size = Get-OneLinkPackageSizeText -Folder $folder -Display $row.Package
            $script:PackagePlan.Add($row)
            $rowCount++
        }
    }
    Invoke-GridRefresh $PackageGrid

    if ($rowCount -eq 0) {
        Write-OneLinkLog "Package plan: no connected server is marked with a package role." -Level Warning
        Show-WarningMessage "No connected server is marked AppServer / Concentrator / ReportServer / nConnect / WebEvents / Auxiliary Service. Mark roles in the Servers grid, connect, then build the plan."
    }
    else {
        $folderNote = if ($roots.Count -gt 1) { "$($roots.Count) folders (searched recursively)" } else { "$($roots[0]) (searched recursively)" }
        Write-OneLinkLog "Package plan built: $rowCount item(s) from $($files.Count) package(s) found under $folderNote. Review/edit, then Upload." -Level Success
    }
}

