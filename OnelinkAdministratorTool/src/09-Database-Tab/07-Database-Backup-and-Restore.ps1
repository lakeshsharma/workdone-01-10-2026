# Self-contained worker: export a database to Server / Local / Network.
$script:ExportWorker = {
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($DatabaseFunctions))
    function q($v) { "'" + ([string]$v -replace "'", "'\''") + "'" }
    $downloadDir = $null
    $sess = $null
    try {
        if (($env:PSModulePath -split ';') -notcontains $ModulesRoot) { $env:PSModulePath = $ModulesRoot + ';' + $env:PSModulePath }
        Import-Module Posh-SSH -ErrorAction Stop
        $pfx = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
        $sec = ConvertTo-SecureString $SrvPass -AsPlainText -Force
        $cred = [pscredential]::new($SrvUser, $sec)
        $sync.Status = "Connecting to $SrvHost ..."
        $sess = New-SSHSession -ComputerName $SrvHost -Port $SrvPort -Credential $cred -AcceptKey -ErrorAction Stop
        $sync.Client = $sess.Session
        if ($sync.Cancel) { throw 'Stopped.' }

        if ($Loc -like 'Server*') {
            $sync.Status = "Exporting '$Db' on $SrvHost to $File (large DBs can take a long time) ..."
            $databaseCommand = New-OneLinkDatabaseExportCommand -DatabaseName $Db -FilePath $(if ($Loc -like 'Server*') { $File } else { $rtmp })
            $r = Invoke-SSHCommand -SSHSession $sess -Command (New-OneLinkDatabaseJobCommand -Command $databaseCommand -JobId $JobId) -TimeOut $Timeout
            if ($r.ExitStatus -ne 0) { throw ("Database command failed (exit {0}). {1}" -f $r.ExitStatus, ((@($r.Output) + @($r.Error)) -join " ")) }
            if ($sync.Cancel) { throw 'Stopped.' }
            $sync.Ok = $true; $sync.Message = "Exported '$Db' to $File on $SrvHost."
        }
        else {
            $base = (($File -split '[\\/]') | Where-Object { $_ -ne '' } | Select-Object -Last 1); if (-not $base) { $base = 'onelink_db_export.sql.gz' }
            $rtmp = "$UploadDir/olk_backup_$([guid]::NewGuid().ToString('N'))$(if ($File.EndsWith('.gz')) { '.sql.gz' } else { '.sql' })"
            $sync.Status = "Exporting '$Db' on $SrvHost (temp) ..."
            $databaseCommand = New-OneLinkDatabaseExportCommand -DatabaseName $Db -FilePath $(if ($Loc -like 'Server*') { $File } else { $rtmp })
            $r = Invoke-SSHCommand -SSHSession $sess -Command (New-OneLinkDatabaseJobCommand -Command $databaseCommand -JobId $JobId) -TimeOut $Timeout
            if ($r.ExitStatus -ne 0) { throw ("Database command failed (exit {0}). {1}" -f $r.ExitStatus, ((@($r.Output) + @($r.Error)) -join " ")) }
            if ($sync.Cancel) { throw 'Stopped.' }
            $chk = Invoke-SSHCommand -SSHSession $sess -Command ("test -f " + (q $rtmp) + " && echo OLK_HAVE || echo OLK_MISS") -TimeOut 20
            if (([string]$chk.Output) -notmatch 'OLK_HAVE') { throw ("Database export did not create '$rtmp' on $SrvHost. " + ((@($r.Output, $r.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()) }
            if ($Loc -like 'Network*') {
                $rootShare = if ($File -match '^(\\\\[^\\]+\\[^\\]+)') { $matches[1] } else { $File }
                if (-not [string]::IsNullOrWhiteSpace($NetUser)) { Invoke-OneLinkNetUse use $rootShare $NetPass "/user:$NetUser" | Out-Null }
                else { Invoke-OneLinkNetUse use $rootShare | Out-Null }
            }
            $destDir = [IO.Path]::GetDirectoryName($File)
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            $sync.Status = "Downloading backup to $File (large DBs can take a long time) ..."
            $downloadDir = Join-Path ([IO.Path]::GetTempPath()) ('olk_download_' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $downloadDir)
            Get-SCPItem -ComputerName $SrvHost -Port $SrvPort -Credential $cred -Path $rtmp -PathType File -Destination $downloadDir -AcceptKey -Force -ErrorAction Stop
            $downloaded = Join-Path $downloadDir (($rtmp -split '/')[-1])
            if ($sync.Cancel) { throw 'Stopped.' }
            Move-Item -LiteralPath $downloaded -Destination $File -Force
            if ($sync.Cancel) { throw 'Stopped.' }
            Invoke-SSHCommand -SSHSession $sess -Command ("sudo rm -f " + (q $rtmp) + " 2>/dev/null; true") -TimeOut 30 | Out-Null
            $sync.Ok = $true; $sync.Message = "Exported '$Db' from $SrvHost to $File."
        }
    }
    catch {
        if ($sync.Cancel) { $sync.Ok = $false; $sync.Message = 'Stopped by user.' }
        else { $sync.Ok = $false; $sync.Message = $_.Exception.Message }
    }
    finally {
        try { if ($sess) { Remove-SSHSession -SSHSession $sess -ErrorAction SilentlyContinue | Out-Null } } catch { }
        if ($downloadDir -and (Test-Path -LiteralPath $downloadDir)) {
            $resolved = [IO.Path]::GetFullPath($downloadDir)
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'olk_download_*') { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $sync.Done = $true
    }
}

# Self-contained worker: import a database from Server / Local / Network / Another VM.
$script:ImportWorker = {
    $ErrorActionPreference = 'Stop'
    . ([scriptblock]::Create($DatabaseFunctions))
    function q($v) { "'" + ([string]$v -replace "'", "'\''") + "'" }
    $remoteImportDir = $null
    $sess = $null; $pcTmp = $null
    try {
        if (($env:PSModulePath -split ';') -notcontains $ModulesRoot) { $env:PSModulePath = $ModulesRoot + ';' + $env:PSModulePath }
        Import-Module Posh-SSH -ErrorAction Stop
        $pfx = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
        $sec = ConvertTo-SecureString $SrvPass -AsPlainText -Force
        $cred = [pscredential]::new($SrvUser, $sec)
        $sync.Status = "Connecting to $SrvHost ..."
        $sess = New-SSHSession -ComputerName $SrvHost -Port $SrvPort -Credential $cred -AcceptKey -ErrorAction Stop
        $sync.Client = $sess.Session
        if ($sync.Cancel) { throw 'Stopped.' }

        $rfile = $File
        $cleanup = $false
        if ($Loc -notlike 'Server*') {
            $localFile = $null
            if ($Loc -like 'Local*') {
                if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Local file not found: $File" }
                $localFile = $File
            }
            elseif ($Loc -like 'Network*') {
                $rootShare = if ($File -match '^(\\\\[^\\]+\\[^\\]+)') { $matches[1] } else { $File }
                if (-not [string]::IsNullOrWhiteSpace($NetUser)) { Invoke-OneLinkNetUse use $rootShare $NetPass "/user:$NetUser" | Out-Null }
                else { Invoke-OneLinkNetUse use $rootShare | Out-Null }
                if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "File not found or share not reachable: $File" }
                $localFile = $File
            }
            elseif ($Loc -like 'Another VM*') {
                $vsec = ConvertTo-SecureString $VmPass -AsPlainText -Force
                $vcred = [pscredential]::new($VmUser, $vsec)
                $pcTmp = Join-Path ([IO.Path]::GetTempPath()) ("olk_" + [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $pcTmp -Force | Out-Null
                $sync.Status = "Downloading backup from $VmHost (can take a long time) ..."
                Get-SCPItem -ComputerName $VmHost -Port 22 -Credential $vcred -Path $File -PathType File -Destination $pcTmp -AcceptKey -Force -ErrorAction Stop
                $leaf = (($File -split '[\\/]') | Where-Object { $_ -ne '' } | Select-Object -Last 1)
                $localFile = Join-Path $pcTmp $leaf
            }
            if ($sync.Cancel) { throw 'Stopped.' }
            # Make sure the server-side temp dir exists/writable before the upload.
            $remoteImportDir = "$UploadDir/olk_restore_$JobId"
            $prep = Invoke-SSHCommand -SSHSession $sess -Command ('umask 077; mkdir -- ' + (q $remoteImportDir)) -TimeOut 30
            if ($prep.ExitStatus -ne 0) { throw 'Could not create the restore staging directory.' }
            $sync.Status = "Uploading backup to $SrvHost (can take a long time) ..."
            Set-SCPItem -ComputerName $SrvHost -Port $SrvPort -Credential $cred -Path $localFile -Destination $remoteImportDir -AcceptKey -ErrorAction Stop
            $rfile = "$remoteImportDir/" + [IO.Path]::GetFileName($localFile)
            $cleanup = $true
            if ($sync.Cancel) { throw 'Stopped.' }
        }
        $sync.Status = "Restoring '$Db' on $SrvHost (large DBs can take a long time) ..."
            $databaseCommand = New-OneLinkDatabaseImportCommand -DatabaseName $Db -FilePath $rfile
            $r = Invoke-SSHCommand -SSHSession $sess -Command (New-OneLinkDatabaseJobCommand -Command $databaseCommand -JobId $JobId) -TimeOut $Timeout
            if ($r.ExitStatus -ne 0) { throw ("Database command failed (exit {0}). {1}" -f $r.ExitStatus, ((@($r.Output) + @($r.Error)) -join " ")) }
        if ($sync.Cancel) { throw 'Stopped.' }
        if ($cleanup) { Invoke-SSHCommand -SSHSession $sess -Command ("rm -f -- " + (q $rfile) + "; rmdir -- " + (q $remoteImportDir)) -TimeOut 30 | Out-Null }
        $sync.Ok = $true; $sync.Message = "Imported into '$Db' on $SrvHost."
    }
    catch {
        if ($sync.Cancel) { $sync.Ok = $false; $sync.Message = 'Stopped by user.' }
        else { $sync.Ok = $false; $sync.Message = $_.Exception.Message }
    }
    finally {
        try { if ($sess) { Remove-SSHSession -SSHSession $sess -ErrorAction SilentlyContinue | Out-Null } } catch { }
        if ($pcTmp) {
            $resolved = [IO.Path]::GetFullPath($pcTmp)
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^olk_[a-f0-9]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $sync.Done = $true
    }
}

$BtnExportDb.Add_Click({
    if ($script:BgState.Job) { Show-ErrorMessage "A backup/restore is already running. Stop it or wait for it to finish."; return }
    if ([string]::IsNullOrWhiteSpace($CmbExportDb.Text)) { Show-ErrorMessage "Select or type the database to back up."; return }
    if ([string]::IsNullOrWhiteSpace($TxtExportFile.Text)) { Show-ErrorMessage "Enter the backup file path."; return }
    $srv = Get-OneLinkDbTargetServer
    if ($null -eq $srv) { return }
    $db = $CmbExportDb.Text.Trim()
    $file = $TxtExportFile.Text.Trim()
    $loc = Get-ComboText $CmbExportDest
    $uploadDir = ([string]$script:Settings.Remote.UploadDirectory).TrimEnd('/')
    try {
        if ($loc -like 'Network*' -and $file -notmatch '^\\\\') { throw "Network location needs a UNC path, e.g. \\server\share\db.sql.gz" }
        if ($loc -like 'Local*' -and [string]::IsNullOrWhiteSpace([IO.Path]::GetDirectoryName($file))) { throw "Enter a full local path, e.g. C:\backups\db.sql.gz" }
        if ($loc -notlike 'Server*') {
            Ensure-OneLinkRemoteDirectory -Session $srv.Session -RemoteDirectory $uploadDir -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds)
        }
    }
    catch { Show-ErrorMessage $_.Exception.Message; return }

    $vars = @{
        SrvHost = [string]$srv.Host; SrvPort = [int]$srv.Port; SrvUser = $srv.Credential.UserName; SrvPass = $srv.Credential.GetNetworkCredential().Password
        Db = $db; Loc = $loc; File = $file; UploadDir = $uploadDir; Timeout = $script:BackupTimeoutSeconds
        DatabaseFunctions = Get-OneLinkDatabaseWorkerFunctions
        ModulesRoot = (Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\Modules')
        NetUser = $TxtExportNetUser.Text; NetPass = $PwdExportNetPass.Password
        VmHost = ''; VmUser = ''; VmPass = ''
    }
    $vars.JobId = [guid]::NewGuid().ToString('N')
    $ctx = Start-OneLinkBgJob -Script $script:ExportWorker -Vars $vars
    $ctx.Sync.StopInfo = @{ Host = [string]$srv.Host; Port = [int]$srv.Port; User = $srv.Credential.UserName; Pass = $srv.Credential.GetNetworkCredential().Password; JobId = $vars.JobId }
    Write-OneLinkLog "[$($srv.Host)] Backup (Export) started: '$db' -> $loc : $file" -Level Info
    Watch-OneLinkBgJob -Ctx $ctx -StatusCtrl $TxtExportStatus -RunButton $BtnExportDb -StopButton $BtnStopExport -OpName 'Export Database' -TargetHost ([string]$srv.Host)
})

$BtnStopExport.Add_Click({ if ($script:BgState.Job) { Stop-OneLinkBgJob -Ctx $script:BgState.Job } })

$BtnImportDb.Add_Click({
    if ($script:BgState.Job) { Show-ErrorMessage "A backup/restore is already running. Stop it or wait for it to finish."; return }
    if ([string]::IsNullOrWhiteSpace($CmbImportDb.Text)) { Show-ErrorMessage "Select or type the database to restore into."; return }
    if ([string]::IsNullOrWhiteSpace($TxtImportFile.Text)) { Show-ErrorMessage "Enter the backup file path."; return }
    $srv = Get-OneLinkDbTargetServer
    if ($null -eq $srv) { return }
    $db = $CmbImportDb.Text.Trim()
    $file = $TxtImportFile.Text.Trim()
    $loc = Get-ComboText $CmbImportSrc
    $uploadDir = ([string]$script:Settings.Remote.UploadDirectory).TrimEnd('/')

    $ans = [System.Windows.MessageBox]::Show(
        "Restore database '$db' on $($srv.Host) from '$file' ($loc)?" + [Environment]::NewLine + "This DROPS and recreates the selected database, replacing all of its existing data.",
        'Restore (Import) Database', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    try {
        if ($loc -like 'Network*' -and $file -notmatch '^\\\\') { throw "Network location needs a UNC path, e.g. \\server\share\db.sql.gz" }
        if ($loc -like 'Local*' -and -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Local file not found: $file" }
        if ($loc -like 'Another VM*') {
            if ([string]::IsNullOrWhiteSpace($TxtImportVmHost.Text)) { throw "Another VM: enter the VM host / IP." }
            if ([string]::IsNullOrWhiteSpace($TxtImportVmUser.Text)) { throw "Another VM: enter the SSH username." }
            if ([string]::IsNullOrWhiteSpace($PwdImportVmPass.Password)) { throw "Another VM: enter the SSH password." }
            if ($file -notmatch '^/') { throw "Another VM path must be an absolute Linux path, e.g. /mysqldata/db.sql.gz" }
        }
        if ($loc -notlike 'Server*') {
            Ensure-OneLinkRemoteDirectory -Session $srv.Session -RemoteDirectory $uploadDir -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds)
        }
    }
    catch { Show-ErrorMessage $_.Exception.Message; return }

    $vars = @{
        SrvHost = [string]$srv.Host; SrvPort = [int]$srv.Port; SrvUser = $srv.Credential.UserName; SrvPass = $srv.Credential.GetNetworkCredential().Password
        Db = $db; Loc = $loc; File = $file; UploadDir = $uploadDir; Timeout = $script:BackupTimeoutSeconds
        DatabaseFunctions = Get-OneLinkDatabaseWorkerFunctions
        ModulesRoot = (Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\Modules')
        NetUser = $TxtImportNetUser.Text; NetPass = $PwdImportNetPass.Password
        VmHost = $TxtImportVmHost.Text.Trim(); VmUser = $TxtImportVmUser.Text.Trim(); VmPass = $PwdImportVmPass.Password
    }
    $vars.JobId = [guid]::NewGuid().ToString('N')
    $ctx = Start-OneLinkBgJob -Script $script:ImportWorker -Vars $vars
    $ctx.Sync.StopInfo = @{ Host = [string]$srv.Host; Port = [int]$srv.Port; User = $srv.Credential.UserName; Pass = $srv.Credential.GetNetworkCredential().Password; JobId = $vars.JobId }
    Write-OneLinkLog "[$($srv.Host)] Restore (Import) started: '$db' <- $loc : $file" -Level Info
    Watch-OneLinkBgJob -Ctx $ctx -StatusCtrl $TxtImportStatus -RunButton $BtnImportDb -StopButton $BtnStopImport -OpName 'Import Database' -TargetHost ([string]$srv.Host)
})

$BtnStopImport.Add_Click({ if ($script:BgState.Job) { Stop-OneLinkBgJob -Ctx $script:BgState.Job } })

