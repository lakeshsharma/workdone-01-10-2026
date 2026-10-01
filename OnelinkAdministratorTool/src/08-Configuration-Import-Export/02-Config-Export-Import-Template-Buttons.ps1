$BtnExportConfig.Add_Click({
    try {
        $sfd = New-Object Microsoft.Win32.SaveFileDialog
        $sfd.Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        $sfd.FileName = "$($script:AppName)-config.xlsx"
        if (-not $sfd.ShowDialog()) { return }

        $serverRows = New-Object System.Collections.Generic.List[object]
        $settingRows = New-Object System.Collections.Generic.List[object]
        # Server inventory (Password intentionally BLANK - the user fills it before importing).
        foreach ($s in $script:Servers) {
            if ([string]::IsNullOrWhiteSpace($s.Host)) { continue }
            $serverRows.Add([pscustomobject]@{ Host = [string]$s.Host; Port = [string]$s.Port; Username = [string]$s.Username; Password = ''; Roles = [string]$s.Roles; OS = [string]$s.Os })
        }
        # Form settings, grouped into their tabs.
        foreach ($f in (Get-OneLinkConfigFields)) {
            $value = if ($f.Type -eq 'combo') { Get-ComboText $f.Ctrl } else { [string]$f.Ctrl.Text }
            $settingRows.Add([pscustomobject]@{ Key = $f.Key; Value = $value; Section = $f.Section })
        }

        $sheets = Get-OneLinkConfigSheets -ServerRows $serverRows.ToArray() -SettingRows $settingRows.ToArray()
        New-OneLinkXlsx -Path $sfd.FileName -Sheets $sheets

        $svrCount = $serverRows.Count
        Write-OneLinkLog "Configuration exported to $($sfd.FileName): $svrCount server(s) + all options (Excel workbook)." -Level Success
        Show-InfoMessage ("Configuration saved to:`n$($sfd.FileName)`n`n" +
            "A colour Excel workbook with separate tabs: Servers, Database, Package, Certificate, Service.`n" +
            "The Password column is BLANK on purpose - fill it in before importing.`n`n" +
            "You can edit it in Excel and load it back with Import Config.")
    }
    catch {
        Show-ErrorMessage "Export failed. $($_.Exception.Message)"
    }
})

$BtnTemplateConfig.Add_Click({
    try {
        $sfd = New-Object Microsoft.Win32.SaveFileDialog
        $sfd.Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        $sfd.FileName = "$($script:AppName)-config-template.xlsx"
        if (-not $sfd.ShowDialog()) { return }

        # Example server rows the user edits / duplicates.
        $exampleServers = @(
            [pscustomobject]@{ Host = '192.168.1.10'; Port = '22'; Username = 'user'; Password = '<ssh-password>'; Roles = 'AppServer, Database master'; OS = '' },
            [pscustomobject]@{ Host = '192.168.1.11'; Port = '22'; Username = 'user'; Password = '<ssh-password>'; Roles = 'Concentrator'; OS = '' }
        )
        # Example value per option so the user sees what each expects (blank is fine).
        $examples = @{
            DbUser = 'appuser'; DbAllowedIp = '%'; DatabaseName = 'onelink'; GrantUser = 'appuser'; GrantHost = '%'
            ExportDatabase = 'onelink'; ExportFile = '/mysqldata/ndb_export.sql.gz'; ImportDatabase = 'onelink'; ImportFile = '/mysqldata/ndb_export.sql.gz'
            PackageFolder = 'C:\Packages'; RemoteDirectory = '/tmp/onelink-admin-tool'; InstallReason = "Installed via $($script:AppName)"; InstallMode = 'Install'; SslAfterInstall = 'No change'
            ServiceAction = 'Restart'
            CertFile = 'C:\certs\server.pem'; CertDestination = '/opt/onelink/etc/'; CertType = 'Certificates'; CertScanPath = '/opt/onelink/etc/'
        }

        $settingRows = New-Object System.Collections.Generic.List[object]
        foreach ($f in (Get-OneLinkConfigFields)) {
            $ex = if ($examples.ContainsKey($f.Key)) { [string]$examples[$f.Key] } else { '' }
            $settingRows.Add([pscustomobject]@{ Key = $f.Key; Value = $ex; Section = $f.Section })
        }

        $sheets = Get-OneLinkConfigSheets -ServerRows $exampleServers -SettingRows $settingRows.ToArray()
        New-OneLinkXlsx -Path $sfd.FileName -Sheets $sheets

        Write-OneLinkLog "Template written: $($sfd.FileName)." -Level Success
        Show-InfoMessage ("Fill-in template saved to:`n$($sfd.FileName)`n`n" +
            "Colour Excel workbook with tabs: Servers, Database, Package, Certificate, Service.`n" +
            "Replace the example rows/values with your own (blank is fine), add each server's password, then use Import Config.")
    }
    catch {
        Show-ErrorMessage "Template export failed. $($_.Exception.Message)"
    }
})

$BtnImportConfig.Add_Click({
    try {
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Filter = "Config file (*.xlsx;*.csv)|*.xlsx;*.csv|Excel workbook (*.xlsx)|*.xlsx|CSV config (*.csv)|*.csv|All files (*.*)|*.*"
        if (-not $ofd.ShowDialog()) { return }

        $fields = @{}
        foreach ($f in (Get-OneLinkConfigFields)) { $fields[$f.Key] = $f }
        $settingCount = 0
        $newServers = New-Object System.Collections.Generic.List[object]

        # Apply one setting key/value to its control. Returns 1 if applied, else 0.
        $applySetting = {
            param($key, $value)
            if ($fields.ContainsKey($key)) {
                $ff = $fields[$key]
                if ($ff.Type -eq 'combo') { Set-OneLinkComboByText -ComboBox $ff.Ctrl -Text $value } else { $ff.Ctrl.Text = $value }
                return 1
            }
            return 0
        }
        # Build an OlServer from parts (skips the template placeholder password).
        $makeServer = {
            param($h, $port, $user, $roles, $os, $pw)
            $srv = [OlServer]::new()
            $srv.Host = [string]$h
            $pp = 22; [void][int]::TryParse([string]$port, [ref]$pp); $srv.Port = $pp
            $srv.Username = [string]$user
            $srv.Roles = [string]$roles
            $srv.RolesDisplay = if ([string]::IsNullOrWhiteSpace($srv.Roles)) { 'Select...' } else { $srv.Roles }
            $srv.Os = [string]$os
            if (-not [string]::IsNullOrEmpty([string]$pw) -and ([string]$pw) -ne '<ssh-password>') {
                $srv.SecurePassword = ConvertTo-SecureString ([string]$pw) -AsPlainText -Force
                $srv.PasswordDisplay = ([string][char]0x25CF) * 6
            }
            return $srv
        }

        if ([IO.Path]::GetExtension($ofd.FileName) -ieq '.xlsx') {
            # ---- Excel workbook (tabs: Servers, Database, Package, Certificate, Service) ----
            $book = Import-OneLinkXlsx -Path $ofd.FileName
            foreach ($sheetName in $book.Keys) {
                $rows = @($book[$sheetName])
                if ($rows.Count -lt 1) { continue }
                if ($sheetName -eq 'Servers') {
                    for ($i = 1; $i -lt $rows.Count; $i++) {   # row 0 is the header
                        $r = @($rows[$i]); if ($r.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$r[0])) { continue }
                        $g = { param($a, $j) if ($j -lt $a.Count) { [string]$a[$j] } else { '' } }
                        $newServers.Add((& $makeServer (& $g $r 0) (& $g $r 1) (& $g $r 2) (& $g $r 4) (& $g $r 5) (& $g $r 3)))
                    }
                }
                else {
                    # Option / Value tab -> settings
                    for ($i = 1; $i -lt $rows.Count; $i++) {
                        $r = @($rows[$i]); if ($r.Count -lt 1) { continue }
                        $key = [string]$r[0]; $val = if ($r.Count -ge 2) { [string]$r[1] } else { '' }
                        $settingCount += (& $applySetting $key $val)
                    }
                }
            }
        }
        else {
            # ---- CSV (current + legacy formats) ----
            $data = @(Import-Csv -LiteralPath $ofd.FileName)
            if ($data.Count -eq 0) { Show-WarningMessage "The file is empty."; return }
            $hasRecordType = @($data | Get-Member -MemberType NoteProperty -Name RecordType).Count -gt 0
            if (-not $hasRecordType) {
                foreach ($record in $data) { $settingCount += (& $applySetting ([string]$record.Key) ([string]$record.Value)) }
            }
            else {
                foreach ($record in $data) {
                    $rt = [string]$record.RecordType
                    if ($rt -eq 'Server') {
                        if ([string]::IsNullOrWhiteSpace($record.Host)) { continue }
                        $newServers.Add((& $makeServer ([string]$record.Host) ([string]$record.Port) ([string]$record.Username) ([string]$record.Roles) ([string]$record.OS) ([string]$record.Password)))
                    }
                    elseif ($rt -eq 'Setting') {
                        $settingCount += (& $applySetting ([string]$record.SettingName) ([string]$record.SettingValue))
                    }
                }
            }
        }

        # Load the imported servers into the grid.
        if ($newServers.Count -gt 0) {
            $existing = @($script:Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Host) })
            $replace = $true
            if ($existing.Count -gt 0) {
                $ans = [System.Windows.MessageBox]::Show(
                    "The file has $($newServers.Count) server(s). Replace the current $($existing.Count) server row(s), or append?" + [Environment]::NewLine +
                    "Yes = replace   .   No = append   .   Cancel = keep only settings",
                    'Import servers', 'YesNoCancel', 'Question')
                if ($ans -eq 'Cancel') { $newServers.Clear() }
                elseif ($ans -eq 'No') { $replace = $false }
            }
            if ($newServers.Count -gt 0) {
                if ($replace) {
                    foreach ($s in $script:Servers) { if ($null -ne $s.Session) { try { Disconnect-OneLinkSsh -Session $s.Session } catch { } } }
                    $script:Servers.Clear()
                }
                foreach ($s in $newServers) { $script:Servers.Add($s) }
                Invoke-GridRefresh $ServerGrid
                Update-ConnectionSummary
                Update-TargetCombos
                Update-DbTargetCombo
            }
        }

        Write-OneLinkLog "Configuration imported from $($ofd.FileName): $($newServers.Count) server(s), $settingCount setting(s)." -Level Success
        Show-InfoMessage ("Imported from:`n$($ofd.FileName)`n`n" +
            "$($newServers.Count) server(s) and $settingCount setting(s) applied.`n" +
            "For any server whose Password was left blank, click its Password cell to set it before connecting.")
    }
    catch {
        Show-ErrorMessage "Import failed. $($_.Exception.Message)"
    }
})

