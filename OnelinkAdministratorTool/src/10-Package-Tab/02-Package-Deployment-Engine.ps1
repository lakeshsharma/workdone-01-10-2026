# RPM/DEB package name that each role installs (used to read the currently
# installed version so we can warn on a downgrade). AppServer's package is the
# base 'onelink'; the others match their role.
$script:RolePackageName = @{
    'AppServer'    = 'onelink'
    'Concentrator' = 'onelink-concentrator'
    'ReportServer' = 'onelink-report-server'
    'nConnect'     = 'onelink-nconnect'
    'WebEvents'    = 'onelink-webevents'
}

# Read the installed version of a package on the server (or $null if absent).
function Get-OneLinkInstalledPackageVersion {
    param($Session, [string]$Os, [string]$PkgName)
    $q = ConvertTo-OneLinkBashArg $PkgName
    if ($Os -eq 'debian') {
        $cmd = "dpkg-query -W -f='" + '${Version}' + "' $q 2>/dev/null"
    }
    else {
        $cmd = "rpm -q --qf '%{VERSION}-%{RELEASE}' $q 2>/dev/null"
    }
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 30
    $t = ([string]$r.Output).Trim()
    if ([string]::IsNullOrWhiteSpace($t) -or $t -match '(?i)not installed') { return $null }
    return (Get-OlPackageVersion $t)
}

# Enable + start a systemd service (systemctl enable --now). Success judged by
# is-active, not the exit code.
function Invoke-OneLinkEnableStartService {
    param($Session, $Settings, [string]$Unit)
    $u = ConvertTo-OneLinkBashArg ($Unit + '.service')
    $cmd = "sudo systemctl enable --now $u >/dev/null 2>&1; echo OLK_ACTIVE=`$(systemctl is-active $u 2>/dev/null)"
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
    $t = (@($r.Output, $r.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    if ($t -match 'OLK_ACTIVE=active') { return "enabled & started (active)" }
    $state = if ($t -match 'OLK_ACTIVE=(\S+)') { $Matches[1] } else { 'unknown' }
    throw "service not active after 'enable --now' (state: $state)."
}

# A Yes/No confirmation that REQUIRES a risk checkbox to be ticked before Yes is
# enabled. Returns $true only if the user ticked the box AND clicked Yes.
function Show-OneLinkRiskConfirm {
    param([string]$Message, [string]$CheckboxText, [string]$Title = 'Confirm')
    $win = New-Object System.Windows.Window
    $win.Title = $Title
    $win.SizeToContent = 'WidthAndHeight'
    $win.WindowStartupLocation = 'CenterScreen'
    $win.ResizeMode = 'NoResize'
    $win.MinWidth = 460
    if ($script:Window) { $win.Owner = $script:Window }
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '18'
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Message; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,0,0,12'; $tb.MaxWidth = 460
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $CheckboxText; $chk.Margin = '0,0,0,14'
    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'
    $yes = New-Object System.Windows.Controls.Button
    $yes.Content = 'Yes, proceed'; $yes.Width = 110; $yes.Margin = '0,0,8,0'; $yes.IsEnabled = $false
    $no = New-Object System.Windows.Controls.Button
    $no.Content = 'Cancel'; $no.Width = 90
    $chk.Add_Click({ $yes.IsEnabled = [bool]$chk.IsChecked }.GetNewClosure())
    # A .GetNewClosure() block writes $script:X to the CLOSURE's own module scope,
    # not the real script variable (the same trap fixed for $script:BgState in
    # 09-Database-Tab\06-Background-Job-Runner.ps1) - so the result is held in a
    # captured hashtable instead, which a closure CAN mutate.
    $result = @{ Value = $false }
    $yes.Add_Click({ $result.Value = $true; $win.Close() }.GetNewClosure())
    $no.Add_Click({ $result.Value = $false; $win.Close() }.GetNewClosure())
    [void]$btns.Children.Add($yes); [void]$btns.Children.Add($no)
    [void]$sp.Children.Add($tb); [void]$sp.Children.Add($chk); [void]$sp.Children.Add($btns)
    $win.Content = $sp
    [void]$win.ShowDialog()
    return [bool]$result.Value
}

# Deploy the plan. $Install=$false uploads only; $true uploads and installs.
function Invoke-OneLinkPackageDeployment {
    param([bool]$Install)

    $rows = @($script:PackagePlan | Where-Object { $_.Package -and $_.Package -ne '(skip)' })
    if ($rows.Count -eq 0) { Show-ErrorMessage "No packages to deploy. Build the plan and choose packages first."; return }

    $remoteDir = $TxtRemoteDirectory.Text
    if ([string]::IsNullOrWhiteSpace($remoteDir)) { Show-ErrorMessage "Remote directory is required."; return }
    # Only used as Resolve-OneLinkPackagePath's fallback if a Display string is somehow
    # missing from $script:PackagePathLookup (shouldn't happen - Build-Plan always
    # populates it) - take just the first folder if the box holds several (';'-joined).
    $folder = (([string]$TxtPackagePath.Text) -split ';' | Select-Object -First 1).Trim()
    $mode = Get-ComboText $CmbInstallMode
    $reason = $TxtInstallReason.Text
    $opName = if ($Install) { 'Upload and Install' } else { 'Upload' }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    $ok = New-Object System.Collections.Generic.List[string]
    $fail = New-Object System.Collections.Generic.List[string]
    $depStart = Get-Date

    foreach ($row in $rows) {
        $server = $row.Server
        $start = Get-Date
        try {
            if ($null -eq $server -or $null -eq $server.Session) { throw "server is not connected." }
            $localPath = Resolve-OneLinkPackagePath -Folder $folder -Display $row.Package
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) { throw "package file not found: $($row.Package)" }

            # Downgrade guard: if installing and the selected package version is
            # LOWER than what is already installed, warn and require an explicit
            # "proceed at own risk" tick. Declined -> skip this server.
            if ($Install -and $script:RolePackageName.Contains($row.Role)) {
                $row.Status = 'Checking version...'; Invoke-GridRefresh $PackageGrid
                $fileVer = Get-OlPackageVersion $row.Package
                $instVer = $null
                try { $instVer = Get-OneLinkInstalledPackageVersion -Session $server.Session -Os ([string]$server.Os) -PkgName $script:RolePackageName[$row.Role] } catch { }
                if ($instVer -and $fileVer -lt $instVer) {
                    $proceed = Show-OneLinkRiskConfirm -Title 'Version downgrade warning' `
                        -Message ("[$($server.Host)] $($row.Role): the selected package is a LOWER version than what is already installed." + [Environment]::NewLine + [Environment]::NewLine +
                            "Installed : $instVer" + [Environment]::NewLine +
                            "Selected  : $fileVer   ($($row.Package))" + [Environment]::NewLine + [Environment]::NewLine +
                            "Installing/updating with a LOWER version may BREAK the application and its dependent services.") `
                        -CheckboxText 'I understand the risk and want to install the lower version anyway.'
                    if (-not $proceed) {
                        $row.Status = 'Skipped (downgrade declined)'
                        Write-OneLinkLog "[$($server.Host)] $($row.Role): downgrade $instVer -> $fileVer declined; skipped." -Level Warning
                        Invoke-GridRefresh $PackageGrid
                        continue
                    }
                    Write-OneLinkLog "[$($server.Host)] $($row.Role): downgrade $instVer -> $fileVer accepted at own risk." -Level Warning
                }
            }

            $row.Status = 'Uploading...'; Invoke-GridRefresh $PackageGrid
            Ensure-OneLinkRemoteDirectory -Session $server.Session -RemoteDirectory $remoteDir -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds)
            Write-OneLinkLog "[$($server.Host)] Uploading $($row.Package) ($($row.Role))." -Level Info
            $remotePath = Send-OneLinkPackage -ComputerName $server.Host -Port ([int]$server.Port) -Credential $server.Credential -LocalPath $localPath -RemoteDirectory $remoteDir

            if ($Install) {
                $row.Status = 'Installing...'; Invoke-GridRefresh $PackageGrid
                $out = Install-OneLinkPackage -Session $server.Session -Settings $script:Settings -RemotePackagePath $remotePath -Mode $mode -Reason $reason
                Write-OneLinkLog "[$($server.Host)] $out" -Level Info

                # Optionally configure SSL AFTER install (SSL files exist only now).
                # Concentrator / Report Server go through nmenu (n_ssl_config);
                # AppServer is not covered by nmenu, so it edits app.properties
                # (jetty.ssl.enabled) via Invoke-AppserverSslConfig. Any SSL failure
                # is a non-fatal warning - the package install itself already succeeded.
                $sslAfter = Get-ComboText $CmbSslAfterInstall
                if ($sslAfter -eq 'Enable' -or $sslAfter -eq 'Disable') {
                    if ($row.Role -eq 'AppServer') {
                        $row.Status = "SSL $sslAfter..."; Invoke-GridRefresh $PackageGrid
                        try {
                            $sslOut = Invoke-AppserverSslConfig -Session $server.Session -Settings $script:Settings -Action $sslAfter
                            Write-OneLinkLog "[$($server.Host)] SSL $sslAfter (OneLink Appserver): $sslOut" -Level Success
                            Write-OneLinkLog "[$($server.Host)] Restart onelink-appserver (Service Installer) to apply the SSL change." -Level Warning
                        }
                        catch {
                            Write-OneLinkLog "[$($server.Host)] SSL $sslAfter (OneLink Appserver) failed (install still OK): $($_.Exception.Message)" -Level Warning
                        }
                    }
                    else {
                        $sslComp = switch ($row.Role) { 'Concentrator' { 'Concentrator' } 'ReportServer' { 'Report Server' } default { $null } }
                        if ($sslComp) {
                            $row.Status = "SSL $sslAfter..."; Invoke-GridRefresh $PackageGrid
                            try {
                                $sslOut = Invoke-NMenuSslConfig -Session $server.Session -Settings $script:Settings -Component $sslComp -Action $sslAfter
                                Write-OneLinkLog "[$($server.Host)] SSL $sslAfter ($sslComp): $sslOut" -Level Success
                            }
                            catch {
                                Write-OneLinkLog "[$($server.Host)] SSL $sslAfter ($sslComp) failed (install still OK): $($_.Exception.Message)" -Level Warning
                            }
                        }
                    }
                }

                # Optionally enable + start the service after a successful install.
                if ($ChkEnableStart.IsChecked -and $script:RoleServiceMap.Contains($row.Role)) {
                    $unit = $script:RoleServiceMap[$row.Role]
                    $row.Status = 'Enabling & starting...'; Invoke-GridRefresh $PackageGrid
                    try {
                        $en = Invoke-OneLinkEnableStartService -Session $server.Session -Settings $script:Settings -Unit $unit
                        Write-OneLinkLog "[$($server.Host)] $unit $en" -Level Success
                    }
                    catch {
                        Write-OneLinkLog "[$($server.Host)] enable & start $unit failed (install still OK): $($_.Exception.Message)" -Level Warning
                    }
                }
            }

            $row.Status = if ($Install) { 'Installed' } else { 'Uploaded' }
            $ok.Add("$($server.Host) / $($row.Package)")
            Write-OneLinkEfficiency -Operation "$opName ($($row.Role))" -Target ([string]$server.Host) -Outcome 'Success' -Start $start -End (Get-Date)
        }
        catch {
            $row.Status = "Failed: $($_.Exception.Message)"
            $fail.Add("$($server.Host) / $($row.Package): $($_.Exception.Message)")
            Write-OneLinkLog "[$($server.Host)] $opName failed for $($row.Package). $($_.Exception.Message)" -Level Error
            Write-OneLinkEfficiency -Operation "$opName ($($row.Role))" -Target ([string]$server.Host) -Outcome 'Failed' -Start $start -End (Get-Date)
        }
        Invoke-GridRefresh $PackageGrid
    }

    $script:Window.Cursor = [Windows.Input.Cursors]::Arrow
    $depOutcome = if ($fail.Count -gt 0) { if ($ok.Count -gt 0) { 'Partial' } else { 'Failed' } } else { 'Success' }
    Complete-OneLinkActivity -Name $opName -Target 'plan' -Outcome $depOutcome -OperationSeconds (((Get-Date) - $depStart).TotalSeconds)
    $summary = "$opName" + [Environment]::NewLine +
        "Succeeded ($($ok.Count)): " + ($(if ($ok.Count) { $ok -join ', ' } else { 'none' }))
    if ($fail.Count -gt 0) {
        $summary += [Environment]::NewLine + "Failed ($($fail.Count)):" + [Environment]::NewLine + "  " + ($fail -join ([Environment]::NewLine + "  "))
        Show-WarningMessage $summary
    }
    else {
        Show-InfoMessage $summary
    }
}

