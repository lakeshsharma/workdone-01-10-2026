function Invoke-NMenuServiceAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$SystemdName,
        [Parameter(Mandatory)][ValidateSet('Restart','Stop')][string]$Action
    )
    $verb = if ($Action -eq 'Stop') { 'stop' } else { 'restart' }
    # Direct equivalent of nmenu 'nstart'/'nstop' (with ncheck_os): systemctl on
    # RHEL, service on Debian - no nmenu.
    $tmpl = @'
unit=__UNITQ__
OS=$(uname -r | grep -q "el" && echo redhat || echo debian)
if [ "$OS" = "redhat" ]; then sudo systemctl __VERB__ "$unit"; else sudo service "$unit" __VERB__; fi
'@
    $cmd = $tmpl.Replace('__UNITQ__', (ConvertTo-OneLinkBashArg $SystemdName)).Replace('__VERB__', $verb)
    return Invoke-OneLinkNmenuCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
}

function Get-NMenuServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$SystemdName
    )
    # nstatus exits non-zero when a unit is not running - that is not an error
    # for a status check, so capture the output regardless of exit code.
    # Direct equivalent of nmenu 'nstatus' (+ ncheck_os) - no nmenu.
    $prefixedPath = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
    $statusTmpl = @'
unit=__UNITQ__
OS=$(uname -r | grep -q "el" && echo redhat || echo debian)
if [ "$OS" = "redhat" ]; then sudo SYSTEMD_PAGER= PAGER= systemctl status "$unit"; else sudo SYSTEMD_PAGER= PAGER= service "$unit" status; fi
'@
    $cmd = "$prefixedPath; " + $statusTmpl.Replace('__UNITQ__', (ConvertTo-OneLinkBashArg $SystemdName))
    return Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 30
}

function Invoke-NMenuSslConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][ValidateSet('Concentrator','Report Server')][string]$Component,
        [Parameter(Mandatory)][ValidateSet('Enable','Disable')][string]$Action
    )
    $arg = switch ("$Component|$Action") {
        'Concentrator|Enable'   { 'enable_concentrator' }
        'Concentrator|Disable'  { 'disable_concentrator' }
        'Report Server|Enable'  { 'enable_reportserver' }
        'Report Server|Disable' { 'disable_reportserver' }
        default { throw "No SSL argument mapping for '$Component' / '$Action'." }
    }

    # Direct equivalent of nmenu 'n_ssl_config' - the exact same awk/sed edits to
    # the concentrator activemq.xml and the report-server ssl.properties, run inline
    # so the tool never invokes nmenu. The interactive pause is a no-op here. We
    # still judge success by the "SSL ENABLED/DISABLED" message it prints.
    $prefixedPath = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
    $sslTmpl = @'
CONC_DIR="/opt/onelink-concentrator/conf"
CONC_XML="$CONC_DIR/activemq.xml"
CONC_KEYSTORE="$CONC_DIR/client.ks"
REPORT_DIR="/opt/onelink-report-server/etc"
REPORT_SSL="$REPORT_DIR/ssl.properties"
pause() { :; }
enable_conc_ssl() {
    [ -f "$CONC_XML" ] || { echo "ERROR: $CONC_XML not found"; pause; return; }
    [ -f "$CONC_KEYSTORE" ] || { echo "ERROR: $CONC_KEYSTORE not found"; pause; return; }
    if sudo grep -q '^[[:space:]]*<!-- SSL: UNCOMMENT TO ENABLE' "$CONC_XML"; then
        sudo awk '
        BEGIN { inblock=0 }
        /^[[:space:]]*<!-- SSL: UNCOMMENT TO ENABLE/ { inblock=1; next }
        inblock && /^[[:space:]]*-->$/ { inblock=0; next }
        { print }
        ' "$CONC_XML" | sudo tee "$CONC_XML.tmp" >/dev/null
        sudo mv "$CONC_XML.tmp" "$CONC_XML"
    fi
    if ! sudo grep -q 'NONSSL START' "$CONC_XML"; then
        sudo awk '
        BEGIN { done=0 }
        /^[[:space:]]*<transportConnector name="openwire"/ && !done {
            print "            <!-- NONSSL START"
            print
            getline
            print
            print "                 NONSSL END -->"
            done=1
            next
        }
        { print }
        ' "$CONC_XML" | sudo tee "$CONC_XML.tmp" >/dev/null
        sudo mv "$CONC_XML.tmp" "$CONC_XML"
    fi
    sudo chown onelink:onelink "$CONC_XML"
    sudo chmod 664 "$CONC_XML"
    echo "SSL ENABLED for Concentrator"
    pause
}
disable_conc_ssl() {
    [ -f "$CONC_XML" ] || { echo "ERROR: $CONC_XML not found"; pause; return; }
    if ! sudo grep -q '^[[:space:]]*<!-- SSL: UNCOMMENT TO ENABLE' "$CONC_XML"; then
        sudo awk '
        BEGIN { done=0 }
        /^[[:space:]]*<transportConnector name="ssl"/ && !done {
            print "            <!-- SSL: UNCOMMENT TO ENABLE (must acquire client.ks from Paltronics Support)"
            print
            getline
            print
            print "            -->"
            done=1
            next
        }
        { print }
        ' "$CONC_XML" | sudo tee "$CONC_XML.tmp" >/dev/null
        sudo mv "$CONC_XML.tmp" "$CONC_XML"
    fi
    if sudo grep -q 'NONSSL START' "$CONC_XML"; then
        sudo awk '
        BEGIN { inblock=0 }
        /^[[:space:]]*<!--[[:space:]]*NONSSL START/ { inblock=1; next }
        inblock && /NONSSL END[[:space:]]*-->$/ { inblock=0; next }
        { print }
        ' "$CONC_XML" | sudo tee "$CONC_XML.tmp" >/dev/null
        sudo mv "$CONC_XML.tmp" "$CONC_XML"
    fi
    sudo chown onelink:onelink "$CONC_XML"
    sudo chmod 664 "$CONC_XML"
    echo "SSL DISABLED for Concentrator"
    pause
}
enable_report_ssl() {
    [ -f "$REPORT_SSL" ] || { echo "ERROR: $REPORT_SSL not found"; pause; return; }
    sudo cp -f "$REPORT_SSL" "$REPORT_SSL.bak"
    sudo sed -i 's/^api.use.ssl=.*/api.use.ssl=true/' "$REPORT_SSL"
    sudo chown onelink:onelink "$REPORT_SSL"
    sudo chmod 664 "$REPORT_SSL"
    echo "SSL ENABLED for Report Server"
    pause
}
disable_report_ssl() {
    [ -f "$REPORT_SSL" ] || { echo "ERROR: $REPORT_SSL not found"; pause; return; }
    sudo cp -f "$REPORT_SSL" "$REPORT_SSL.bak"
    sudo sed -i 's/^api.use.ssl=.*/api.use.ssl=false/' "$REPORT_SSL"
    sudo chown onelink:onelink "$REPORT_SSL"
    sudo chmod 664 "$REPORT_SSL"
    echo "SSL DISABLED for Report Server"
    pause
}
case "__ARG__" in
    enable_concentrator)  enable_conc_ssl ;;
    disable_concentrator) disable_conc_ssl ;;
    enable_reportserver)  enable_report_ssl ;;
    disable_reportserver) disable_report_ssl ;;
    *) echo "Invalid option" ;;
esac
'@
    $sslCmd = "$prefixedPath; " + $sslTmpl.Replace('__ARG__', $arg)
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $sslCmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
    $text = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine

    if ($text -match '(?i)SSL\s+(ENABLED|DISABLED)') {
        return $text
    }
    if ($text -match '(?i)not\s+found') {
        # Config file absent -> the component isn't installed on this box yet.
        # Per requirements this is a non-fatal note, not a failure.
        Write-OneLinkLog "SSL $Action ($Component): component not present on this server - $text" -Level Warning
        return $text
    }
    throw "SSL $Action ($Component) did not report success (exit $($result.ExitStatus)). $text"
}

# Enable/Disable SSL for the OneLink Appserver. nmenu's n_ssl_config has NO
# appserver option, so - like the testing team's utility - we do it by editing
# /opt/onelink/etc/app.properties (jetty.ssl.enabled=true|false). For Enable a
# keystore must exist at /opt/onelink/etc/client.ks; the caller may first upload
# one (RemoteKeystorePath) or rely on one already on the box. We do NOT restart
# the service here - the caller tells the user to restart it. Judged by the
# printed marker, not the exit code.
function Invoke-AppserverSslConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][ValidateSet('Enable','Disable')][string]$Action,
        [string]$RemoteKeystorePath
    )

    $val = if ($Action -eq 'Enable') { 'true' } else { 'false' }

    # Optional keystore install block (only when a file was uploaded).
    $ksBlock = ''
    if ($Action -eq 'Enable' -and -not [string]::IsNullOrWhiteSpace($RemoteKeystorePath)) {
        $q = ConvertTo-OneLinkBashArg $RemoteKeystorePath
        $ksBlock = @"
(sudo -n install -m 0644 $q "`$TARGET" || install -m 0644 $q "`$TARGET")
(sudo -n rm -f $q || rm -f $q || true)
"@
    }

    $cmd = @"
set -uo pipefail
PROPS=/opt/onelink/etc/app.properties
TARGET=/opt/onelink/etc/client.ks
stamp=`$(date +%s)
if [ ! -f "`$PROPS" ]; then echo OLK_APPSSL_NOPROPS 1>&2; exit 3; fi
(sudo -n cp "`$PROPS" "`$PROPS.bak_ssl_`$stamp" 2>/dev/null || cp "`$PROPS" "`$PROPS.bak_ssl_`$stamp")
$ksBlock
if [ "$val" = "true" ] && [ ! -f "`$TARGET" ]; then echo OLK_APPSSL_NOKS 1>&2; exit 4; fi
if (sudo -n grep -Eq '^[[:space:]]*jetty\.ssl\.enabled[[:space:]]*=' "`$PROPS" 2>/dev/null || grep -Eq '^[[:space:]]*jetty\.ssl\.enabled[[:space:]]*=' "`$PROPS"); then
  (sudo -n sed -i -E 's/^[[:space:]]*jetty\.ssl\.enabled[[:space:]]*=.*/jetty.ssl.enabled=$val/' "`$PROPS" || sed -i -E 's/^[[:space:]]*jetty\.ssl\.enabled[[:space:]]*=.*/jetty.ssl.enabled=$val/' "`$PROPS")
else
  (printf '\njetty.ssl.enabled=$val\n' | sudo -n tee -a "`$PROPS" >/dev/null || printf '\njetty.ssl.enabled=$val\n' | tee -a "`$PROPS" >/dev/null)
fi
echo OLK_APPSSL_OK
(sudo -n grep -nE 'jetty\.ssl\.enabled|jetty\.ssl\.port|jetty\.ssl\.keystorePath|jetty\.ssl\.trustStorePath' "`$PROPS" || grep -nE 'jetty\.ssl\.enabled|jetty\.ssl\.port|jetty\.ssl\.keystorePath|jetty\.ssl\.trustStorePath' "`$PROPS")
"@

    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
    $text = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine

    if ($text -match 'OLK_APPSSL_OK') { return $text }
    if ($text -match 'OLK_APPSSL_NOPROPS') { throw "SSL $Action (OneLink Appserver): /opt/onelink/etc/app.properties not found - appserver is not installed on this server." }
    if ($text -match 'OLK_APPSSL_NOKS') { throw "SSL Enable (OneLink Appserver): no keystore at /opt/onelink/etc/client.ks. Provide one via 'Appserver keystore' (Browse) or place client.ks on the server first." }
    throw "SSL $Action (OneLink Appserver) did not report success (exit $($result.ExitStatus)). $text"
}

# Install an already-uploaded file (RemoteSource, sitting in the upload dir) to a
# final path on the server, creating parent folders with sudo. Used by the
# Certificates tab to drop a cert/keystore where the user asks. Judged by marker.
function Install-OneLinkCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$RemoteSource,
        [Parameter(Mandatory)][string]$FinalPath,
        [Parameter(Mandatory)][string]$ParentDir
    )
    $qs = ConvertTo-OneLinkBashArg $RemoteSource
    $qf = ConvertTo-OneLinkBashArg $FinalPath
    $qd = ConvertTo-OneLinkBashArg $ParentDir
    $cmd = @"
set -uo pipefail
(sudo -n mkdir -p $qd || mkdir -p $qd)
(sudo -n install -m 0644 $qs $qf || install -m 0644 $qs $qf)
(sudo -n rm -f $qs || rm -f $qs || true)
if [ -f $qf ]; then echo OLK_CERT_OK; (sudo -n ls -l $qf || ls -l $qf); else echo OLK_CERT_FAIL 1>&2; exit 1; fi
"@
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
    $text = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
    if ($text -match 'OLK_CERT_OK') { return $text }
    throw "Certificate install to '$FinalPath' did not confirm (exit $($result.ExitStatus)). $text"
}

# If FinalPath already exists on the server, back it up BEFORE Install-OneLinkCertificate
# overwrites it. No-ops cleanly (returns a 'nothing to back up' message) if there is no
# existing file yet - e.g. a first-time deploy. Never throws: a backup failure is a
# warning, not a reason to abort the deploy.
#   -Dest 'Server'         : sudo-copies it to $BackupPath (an absolute Linux folder) on
#                            the SAME server, right there - no transfer involved.
#   -Dest 'Local Windows'  : stages a copy under the tool's upload dir, then downloads it
#                            to $BackupPath\<server host>\ on this PC. The staged copy is
#                            chown'd back to the CONNECTING user before download - the same
#                            fix as the database-export permission bug: a file a sudo copy
#                            leaves root:0600 cannot be pulled down over SCP by a non-root
#                            login, so every download in this tool must reclaim ownership
#                            first.
function Backup-OneLinkCertificateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$FinalPath,
        [Parameter(Mandatory)][ValidateSet('Server', 'Local Windows')][string]$Dest,
        [Parameter(Mandatory)][string]$BackupPath,
        [string]$ServerHost, [int]$ServerPort, [object]$ServerCredential
    )
    $qf = ConvertTo-OneLinkBashArg $FinalPath
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = [IO.Path]::GetFileName($FinalPath.TrimEnd('/'))
    $timeout = [int]$Settings.Ssh.CommandTimeoutSeconds

    if ($Dest -eq 'Server') {
        $backupDir = $BackupPath.TrimEnd('/'); if ($backupDir -eq '') { $backupDir = '/' }
        $qd = ConvertTo-OneLinkBashArg $backupDir
        $backupFile = "$backupDir/$baseName.$stamp.bak"
        $qb = ConvertTo-OneLinkBashArg $backupFile
        $cmd = @"
set -uo pipefail
if sudo -n test -f $qf 2>/dev/null || test -f $qf 2>/dev/null; then
    (sudo -n mkdir -p -- $qd || mkdir -p -- $qd)
    (sudo -n cp -f -- $qf $qb || cp -f -- $qf $qb)
    if sudo -n test -f $qb 2>/dev/null || test -f $qb 2>/dev/null; then echo "OLK_BK_OK $backupFile"; else echo OLK_BK_FAIL; fi
else
    echo OLK_BK_NONE
fi
"@
        $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds $timeout
        $text = (@($r.Output, $r.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
        if ($text -match 'OLK_BK_NONE') { return "No existing file at $FinalPath - nothing to back up." }
        if ($text -match 'OLK_BK_OK') { return "Backed up existing $FinalPath to $backupFile on the server." }
        return "WARNING: backup of existing $FinalPath failed ($text) - continuing with deploy anyway."
    }

    # Local Windows: stage a connecting-user-owned copy server-side, then SCP it down.
    $remoteDir = ([string]$Settings.Remote.UploadDirectory).TrimEnd('/')
    Ensure-OneLinkRemoteDirectory -Session $Session -RemoteDirectory $remoteDir -TimeoutSeconds $timeout
    $tmp = "$remoteDir/olk_certbak_$([guid]::NewGuid().ToString('N'))_$baseName"
    $qt = ConvertTo-OneLinkBashArg $tmp
    $cmd = @"
set -uo pipefail
if sudo -n test -f $qf 2>/dev/null || test -f $qf 2>/dev/null; then
    (sudo -n cp -f -- $qf $qt || cp -f -- $qf $qt)
    me=`$(id -un)
    (sudo -n chown -- "`$me" $qt 2>/dev/null || true)
    chmod 0644 -- $qt 2>/dev/null || sudo -n chmod 0644 -- $qt 2>/dev/null || true
    if [ -r $qt ]; then echo OLK_BK_OK; else echo OLK_BK_FAIL; fi
else
    echo OLK_BK_NONE
fi
"@
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds $timeout
    $text = (@($r.Output, $r.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    if ($text -match 'OLK_BK_NONE') { return "No existing file at $FinalPath - nothing to back up." }
    if ($text -notmatch 'OLK_BK_OK') { return "WARNING: backup of existing $FinalPath failed ($text) - continuing with deploy anyway." }

    try {
        Import-OneLinkPoshSsh
        $localDir = Join-Path $BackupPath ($ServerHost -replace '[\\/:*?"<>|]', '_')
        if (-not (Test-Path -LiteralPath $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
        $dlDir = Join-Path ([IO.Path]::GetTempPath()) ('olk_certbak_dl_' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $dlDir)
        try {
            Get-SCPItem -ComputerName $ServerHost -Port $ServerPort -Credential $ServerCredential -Path $tmp -PathType File -Destination $dlDir -AcceptKey -Force -ErrorAction Stop
            $downloaded = Join-Path $dlDir ([IO.Path]::GetFileName($tmp))
            $finalLocal = Join-Path $localDir "$baseName.$stamp.bak"
            Move-Item -LiteralPath $downloaded -Destination $finalLocal -Force
        }
        finally {
            if (Test-Path -LiteralPath $dlDir) { Remove-Item -LiteralPath $dlDir -Recurse -Force -ErrorAction SilentlyContinue }
            Invoke-OneLinkSshCommand -Session $Session -Command ("(sudo -n rm -f -- $qt || rm -f -- $qt) 2>/dev/null; true") -TimeoutSeconds 30 | Out-Null
        }
        return "Backed up existing $FinalPath to $finalLocal on this PC."
    }
    catch {
        Invoke-OneLinkSshCommand -Session $Session -Command ("(sudo -n rm -f -- $qt || rm -f -- $qt) 2>/dev/null; true") -TimeoutSeconds 30 | Out-Null
        return "WARNING: backup download of existing $FinalPath failed ($($_.Exception.Message)) - continuing with deploy anyway."
    }
}

