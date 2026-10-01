# Rebuild the "Allowed IP" dropdown choices from the DB target selection:
# % (any host), localhost (local-only), and each selected target's own IP.
# Called by the Db picker's change handler (see Update-OneLinkTargetPicker).
function Update-OneLinkDbAllowedIp {
    $cur = $CmbDbUserIp.Text
    $CmbDbUserIp.Items.Clear()
    [void]$CmbDbUserIp.Items.Add('%')
    [void]$CmbDbUserIp.Items.Add('localhost')
    foreach ($s in @(Get-OneLinkTargetHosts -Key 'Db')) {
        $tgt = [string]$s.Host
        if ($tgt -match '^\d{1,3}(\.\d{1,3}){3}$' -and $CmbDbUserIp.Items -notcontains $tgt) { [void]$CmbDbUserIp.Items.Add($tgt) }
    }
    $CmbDbUserIp.Text = $cur
}

# Allowed IP is LOCKED by default (uses the % default). The user must tick the
# checkbox to set a specific host; unticking it resets to the default (blank -> %).
$ChkSetAllowedIp.Add_Click({
    $CmbDbUserIp.IsEnabled = [bool]$ChkSetAllowedIp.IsChecked
    if (-not $ChkSetAllowedIp.IsChecked) { $CmbDbUserIp.Text = '' }
})

$BtnCreateDbUser.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($TxtDbUser.Text)) { throw "Database username is required." }
        if ($PwdDbUser.Password.Length -eq 0) { throw "Database password is required." }
        if ($PwdDbUser.Password -ne $PwdDbUserConfirm.Password) { throw "The password and re-typed password do not match." }
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
        return
    }

    # Allowed IP only applies when the user ticked the checkbox; otherwise use the
    # default (blank -> '%').
    $allowedIp = if ($ChkSetAllowedIp.IsChecked) { $CmbDbUserIp.Text } else { '' }

    Invoke-MultiServerOperation -Name 'Create DB User' -TargetServers (Get-OneLinkTargetHosts -Key 'Db') -PerServerAction {
        param($server)
        # Blank Allowed IP -> '%' (any host, incl. the local socket) so the
        # account works as 'user'@'%' and `mysql -u user -p` connects locally.
        $out = Invoke-OneLinkCreateDatabaseUser `
            -Session $server.Session `
            -Settings $script:Settings `
            -Username $TxtDbUser.Text `
            -Password $PwdDbUser.Password `
            -AllowedIp $allowedIp
        Write-OneLinkLog "[$($server.Host)] $out" -Level Info
    }
})

$BtnCreateDatabase.Add_Click({
    if ([string]::IsNullOrWhiteSpace($TxtDatabaseName.Text)) { Show-ErrorMessage "Database name is required."; return }
    $dbName = $TxtDatabaseName.Text.Trim()

    # CREATE DATABASE IF NOT EXISTS is evaluated independently on every target.
    Invoke-MultiServerOperation -Name 'Create Database' -TargetServers (Get-OneLinkTargetHosts -Key 'Db') -PerServerAction {
        param($server)
        $out = Invoke-OneLinkCreateDatabase `
            -Session $server.Session `
            -Settings $script:Settings `
            -DatabaseName $TxtDatabaseName.Text.Trim()
        Write-OneLinkLog "[$($server.Host)] $out" -Level Info
    }
})

# Load the user and database lists from the selected target's MySQL.
$BtnRefreshDbLists.Add_Click({
    $srv = Get-OneLinkDbTargetServer
    if ($null -eq $srv) { return }
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $users = Invoke-OneLinkMysqlQuery -Session $srv.Session -Sql "SELECT DISTINCT User FROM mysql.user WHERE User <> '' ORDER BY User"
        $accountHosts = @(Invoke-OneLinkMysqlQuery -Session $srv.Session -Sql 'SELECT DISTINCT Host FROM mysql.user ORDER BY Host')
        $h = $CmbGrantHost.Text; $CmbGrantHost.Items.Clear(); foreach ($x in $accountHosts) { [void]$CmbGrantHost.Items.Add($x) }; $CmbGrantHost.Text = $h
        $dbs   = Invoke-OneLinkMysqlQuery -Session $srv.Session -Sql "SHOW DATABASES"
        $sys = @('information_schema', 'performance_schema', 'mysql', 'sys')
        $dbs = @($dbs | Where-Object { $sys -notcontains $_ })
        # Hide root and MySQL's internal system accounts for safety - the user
        # must not be able to pick them for a grant.
        $sysUsers = @('root', 'mysql.sys', 'mysql.session', 'mysql.infoschema', 'debian-sys-maint', 'mariadb.sys')
        $users = @($users | Where-Object { $sysUsers -notcontains $_ })

        $u = $CmbGrantUser.Text; $CmbGrantUser.Items.Clear(); foreach ($x in $users) { [void]$CmbGrantUser.Items.Add($x) }; $CmbGrantUser.Text = $u
        $d = $CmbGrantDb.Text;   $CmbGrantDb.Items.Clear();   foreach ($x in $dbs)   { [void]$CmbGrantDb.Items.Add($x) };   $CmbGrantDb.Text = $d
        $be = $CmbExportDb.Text; $CmbExportDb.Items.Clear();  foreach ($x in $dbs)   { [void]$CmbExportDb.Items.Add($x) };  $CmbExportDb.Text = $be
        $bi = $CmbImportDb.Text; $CmbImportDb.Items.Clear();  foreach ($x in $dbs)   { [void]$CmbImportDb.Items.Add($x) };  $CmbImportDb.Text = $bi
        Write-OneLinkLog "[$($srv.Host)] Loaded $($users.Count) MySQL user(s) and $($dbs.Count) database(s)." -Level Success
    }
    catch {
        Show-ErrorMessage "Could not load users/databases from $($srv.Host). $($_.Exception.Message)"
    }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
})

$BtnGrantPrivileges.Add_Click({
    if ([string]::IsNullOrWhiteSpace($CmbGrantUser.Text)) { Show-ErrorMessage "Select or type a user to grant."; return }
    if ([string]::IsNullOrWhiteSpace($CmbGrantDb.Text)) { Show-ErrorMessage "Select or type a database to grant on."; return }
    # Optional password: if one is entered, the re-typed value must match (a
    # wrong password would overwrite the user's real password).
    if ($PwdGrant.Password -ne $PwdGrantConfirm.Password) { Show-ErrorMessage "The optional password and its re-typed value do not match."; return }

    Invoke-MultiServerOperation -Name 'Grant Admin Privileges' -TargetServers (Get-OneLinkTargetHosts -Key 'Db') -PerServerAction {
        param($server)
        # Grant to the exact user/host account; a blank password leaves it unchanged.
        $out = Invoke-OneLinkGrantPrivileges `
            -Session $server.Session `
            -Settings $script:Settings `
            -Username $CmbGrantUser.Text.Trim() `
            -AllowedIp $CmbGrantHost.Text.Trim() `
            -DatabaseName $CmbGrantDb.Text.Trim() `
            -Password $PwdGrant.Password
        Write-OneLinkLog "[$($server.Host)] $out" -Level Info
    }
})

