# ---- Certificates tab: browse a local/UNC file, deploy it to the server(s) ----
$BtnBrowseCert.Add_Click({
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Title = "Select certificate / keystore / license file"
    $ofd.Filter = "Cert / keystore / license (*.pem;*.crt;*.cer;*.der;*.cert;*.ca;*.ks;*.jks;*.p12;*.pfx;*.lic;*.key)|*.pem;*.crt;*.cer;*.der;*.cert;*.ca;*.ks;*.jks;*.p12;*.pfx;*.lic;*.key|All files (*.*)|*.*"
    if ($ofd.ShowDialog()) { $TxtCertFile.Text = $ofd.FileName }
})

# Network-login fields are faded until the user ticks the checkbox.
$ChkCertNetAuth.Add_Click({
    $on = [bool]$ChkCertNetAuth.IsChecked
    $TxtCertNetUser.IsEnabled = $on; $PwdCertNetPass.IsEnabled = $on; $BtnCertNetTest.IsEnabled = $on
    if (-not $on) { $TxtCertNetUser.Text = '' }
})

$BtnCertNetTest.Add_Click({
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $res = Test-OneLinkNetworkLogin -Path $TxtCertFile.Text -User $TxtCertNetUser.Text -Password $PwdCertNetPass.Password
        if ($res.Ok) { Write-OneLinkLog $res.Message.Replace([Environment]::NewLine, ' ') -Level Success; Show-InfoMessage $res.Message }
        else { Write-OneLinkLog $res.Message.Replace([Environment]::NewLine, ' ') -Level Warning; Show-WarningMessage $res.Message }
    }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
})

# Backup-destination controls: path/browse are only meaningful for 'Local Windows'
# and 'Server'; swap in a sensible default when the destination TYPE changes (never
# overwrites a value the user already edited for that same type).
$CmbCertBackupDest.Add_SelectionChanged({
    $sel = Get-ComboText $CmbCertBackupDest
    $none = ($sel -eq "Don't back up")
    $TxtCertBackupPath.IsEnabled = -not $none
    $isLocal = $sel -like 'Local Windows*'
    $BtnCertBackupBrowse.IsEnabled = (-not $none) -and $isLocal
    if ($none) { return }
    $cur = $TxtCertBackupPath.Text
    if ($isLocal -and $cur -match '^/') { $TxtCertBackupPath.Text = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'OneLinkAdminTool\CertBackups') }
    elseif ((-not $isLocal) -and ($cur -notmatch '^/')) { $TxtCertBackupPath.Text = '/opt/onelink/cert-backups' }
}.GetNewClosure())

$BtnCertBackupBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select the folder where certificate backups are saved on this PC"
    if (-not [string]::IsNullOrWhiteSpace($TxtCertBackupPath.Text) -and (Test-Path -LiteralPath $TxtCertBackupPath.Text -PathType Container)) {
        $fbd.SelectedPath = $TxtCertBackupPath.Text
    }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $TxtCertBackupPath.Text = $fbd.SelectedPath }
})

$BtnDeployCert.Add_Click({
    $local = ([string]$TxtCertFile.Text).Trim()
    $dest  = ([string]$TxtCertDest.Text).Trim()
    if ($local -eq '') { Show-ErrorMessage "Select a certificate file (Browse...)."; return }

    # Local file OR a UNC path; authenticate to the share only if 'Network login' is ticked.
    $certNetUser = if ($ChkCertNetAuth.IsChecked) { $TxtCertNetUser.Text } else { '' }
    $certNetPass = if ($ChkCertNetAuth.IsChecked) { $PwdCertNetPass.Password } else { '' }
    Connect-OneLinkNetworkPath -Path $local -User $certNetUser -Password $certNetPass
    if (-not (Test-Path -LiteralPath $local -PathType Leaf)) {
        Show-ErrorMessage "File not found or not reachable: $local`n`nIf this is a network path, check the path and the user/password."; return
    }
    if ($dest -eq '') { Show-ErrorMessage "Enter the destination path on the server (e.g. /opt/onelink/etc/client.ks)."; return }
    if ($dest -notmatch '^/') { Show-ErrorMessage "Destination must be an absolute Linux path starting with '/'."; return }

    # Work out the final file path and its parent dir on the Windows side, so the
    # remote command stays simple. A trailing '/' means "keep the source filename".
    if ($dest.EndsWith('/')) { $finalPath = $dest + [IO.Path]::GetFileName($local) } else { $finalPath = $dest }
    $cut = $finalPath.TrimEnd('/').LastIndexOf('/')
    $parentDir = if ($cut -le 0) { '/' } else { $finalPath.Substring(0, $cut) }

    $backupDest = Get-ComboText $CmbCertBackupDest
    $backupPath = ([string]$TxtCertBackupPath.Text).Trim()
    if ($backupDest -ne "Don't back up" -and $backupPath -eq '') { Show-ErrorMessage "Enter (or Browse to) a backup folder, or set 'Back up existing file to' to Don't back up."; return }

    $script:OlCertOk = 0
    Invoke-MultiServerOperation -Name "Deploy certificate" -TargetServers (Get-OneLinkTargetHosts -Key 'Cert') -PerServerAction {
        param($server)
        if ($backupDest -ne "Don't back up") {
            try {
                $bk = Backup-OneLinkCertificateFile -Session $server.Session -Settings $script:Settings -FinalPath $finalPath -Dest $backupDest -BackupPath $backupPath `
                    -ServerHost ([string]$server.Host) -ServerPort ([int]$server.Port) -ServerCredential $server.Credential
                $lvl = if ($bk -match '^WARNING') { 'Warning' } else { 'Info' }
                Write-OneLinkLog "[$($server.Host)] $bk" -Level $lvl
            }
            catch { Write-OneLinkLog "[$($server.Host)] Backup of existing file failed (continuing with deploy): $($_.Exception.Message)" -Level Warning }
        }
        $remoteDir = ([string]$script:Settings.Remote.UploadDirectory).TrimEnd('/')
        Ensure-OneLinkRemoteDirectory -Session $server.Session -RemoteDirectory $remoteDir -TimeoutSeconds ([int]$script:Settings.Ssh.CommandTimeoutSeconds)
        Import-OneLinkPoshSsh
        Set-SCPItem -ComputerName $server.Host -Port ([int]$server.Port) -Credential $server.Credential -Path $local -Destination $remoteDir -AcceptKey -ErrorAction Stop
        $remoteSource = "$remoteDir/" + [IO.Path]::GetFileName($local)
        $out = Install-OneLinkCertificate -Session $server.Session -Settings $script:Settings -RemoteSource $remoteSource -FinalPath $finalPath -ParentDir $parentDir
        Write-OneLinkLog "[$($server.Host)] certificate deployed -> $finalPath" -Level Success
        Write-OneLinkLog "[$($server.Host)] $out" -Level Info
        $script:OlCertOk++
    }
    if ($script:OlCertOk -gt 0) {
        Show-InfoMessage ("Certificate deployed to $finalPath on $($script:OlCertOk) server(s)." + [Environment]::NewLine + [Environment]::NewLine +
            "If a service must load it (e.g. an appserver keystore), restart that service via the Package tab -> Service Installer.")
    }
})

# Map the 'look for' dropdown to a set of file extensions.
function Get-OneLinkCertExts {
    param([string]$TypeSel)
    switch -Wildcard ($TypeSel) {
        'Certificates*' { , @('pem', 'crt', 'cer', 'der', 'cert', 'ca', 'p7b', 'p7c', 'csr', 'crl') }
        'Keystores*'    { , @('ks', 'jks', 'p12', 'pfx', 'keystore', 'truststore', 'jceks', 'bks') }
        'Licenses*'     { , @('lic', 'license') }
        'Keys*'         { , @('key', 'pk8', 'p8') }
        default         { , @('pem', 'crt', 'cer', 'der', 'cert', 'ca', 'p7b', 'p7c', 'csr', 'crl', 'ks', 'jks', 'p12', 'pfx', 'keystore', 'truststore', 'jceks', 'bks', 'lic', 'license', 'key', 'pk8', 'p8') }
    }
}

# List the matching cert/keystore/license files at a path on the server (a folder
# is scanned; a single file returns just itself). Returns file paths, '__NOPATH__'
# if the path doesn't exist, or an empty array if nothing matched.
function Get-OneLinkCertFileList {
    param($Session, $Settings, [string]$Path, [string]$NameExpr)
    # Uses sudo (falling back to non-sudo) so root-owned folders are listed too, and
    # returns ALL matching files (names with spaces/brackets are one-per-line). Tells
    # apart: not-found, permission-denied, and empty-but-readable.
    $tmpl = @'
P=__PATH__
if sudo -n test -f "$P" 2>/dev/null || test -f "$P" 2>/dev/null; then
  printf '%s\n' "$P"
elif sudo -n test -d "$P" 2>/dev/null || test -d "$P" 2>/dev/null; then
  L=$( { sudo -n find "$P" -maxdepth 1 -type f \( __NAMEEXPR__ \) 2>/dev/null || find "$P" -maxdepth 1 -type f \( __NAMEEXPR__ \) 2>/dev/null; } | sort )
  if [ -n "$L" ]; then printf '%s\n' "$L"
  elif sudo -n ls -A "$P" >/dev/null 2>&1 || ls -A "$P" >/dev/null 2>&1; then echo OLK_LIST_NONE
  else echo OLK_LIST_DENIED; fi
else echo OLK_LIST_NOPATH; fi
'@
    $cmd = $tmpl.Replace('__PATH__', (ConvertTo-OneLinkBashArg $Path)).Replace('__NAMEEXPR__', $NameExpr)
    $r = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds 30
    $out = [string]$r.Output
    if ($out -match 'OLK_LIST_NOPATH') { return , @('__NOPATH__') }
    if ($out -match 'OLK_LIST_DENIED') { return , @('__DENIED__') }
    if ($out -match 'OLK_LIST_NONE')   { return @() }
    return @($out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^OLK_LIST_' })
}

# Turn the raw openssl / keytool output for one file into a clean, labelled block.
function Format-OneLinkCertBlock {
    param([string]$Raw)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($Raw -split "`r?`n")) {
        $t = $l.Trim()
        if ($t -eq '' -or $t -match '^===') { continue }
        if ($t -match '^subject=(.+)$') { $out.Add("  Subject    : $($Matches[1].Trim())") }
        elseif ($t -match '^issuer=(.+)$') { $out.Add("  Issuer     : $($Matches[1].Trim())") }
        elseif ($t -match '^notBefore=(.+)$') { $out.Add("  Valid from : $($Matches[1].Trim())") }
        elseif ($t -match '^notAfter=(.+)$') {
            $v = $Matches[1].Trim(); $out.Add("  Expires    : $v")
            try {
                $exp = [datetime]::Parse(($v -replace 'GMT', '').Trim(), [Globalization.CultureInfo]::InvariantCulture)
                $d = [int][math]::Floor(($exp - (Get-Date)).TotalDays)
                $flag = if ($d -lt 0) { "EXPIRED $([math]::Abs($d)) day(s) ago" } elseif ($d -le 30) { "expires in $d day(s) - renew soon" } else { "valid, $d day(s) left" }
                $out.Add("  Health     : $flag")
            }
            catch { }
        }
        elseif ($t -match '(?i)SHA256 Fingerprint=(.+)$') { $out.Add("  SHA-256    : $($Matches[1].Trim())") }
        else { $out.Add("  $t") }
    }
    if ($out.Count -eq 0) { return "  (no readable details)" }
    return ($out -join [Environment]::NewLine)
}

# Inspect any security file that lives on the server. $Path may be a single FILE
# (reported directly) or a FOLDER (scanned for files matching $NameExpr, a find
# name-expression). Each file is identified by CONTENT, not just extension, so the
# reader reports what it actually is even when the extension is misleading:
#   - keystores (.ks/.jks/.p12/.pfx) -> keytool
#   - X.509 certificate (PEM or DER) -> openssl x509 (subject/issuer/expiry/health)
#   - certificate request (CSR)      -> openssl req  (subject)
#   - private key (RSA/EC/PKCS8)     -> reported as a key + size (never dumps key material)
#   - public key                     -> reported as a public key + size
#   - anything else (e.g. .lic)      -> file type, size, and a short text preview
# Tried with sudo first (these files are often root-owned).
function Get-OneLinkCertScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$NameExpr,
        [string]$KeystorePass = 'onelink'
    )
    $tmpl = @'
set -uo pipefail
P=__PATH__
LIST=$(mktemp)
if sudo -n test -f "$P" 2>/dev/null || [ -f "$P" ]; then printf '%s\n' "$P" > "$LIST"
elif sudo -n test -d "$P" 2>/dev/null || [ -d "$P" ]; then { sudo -n find "$P" -maxdepth 1 -type f \( __NAMEEXPR__ \) 2>/dev/null || find "$P" -maxdepth 1 -type f \( __NAMEEXPR__ \) 2>/dev/null; } | sort > "$LIST"
else echo OLK_SCAN_NOPATH; rm -f "$LIST"; exit 0; fi
if [ ! -s "$LIST" ]; then echo OLK_SCAN_NONE; rm -f "$LIST"; exit 0; fi
KT=$(command -v keytool 2>/dev/null || echo /opt/onelink/jre/bin/keytool)
_read() { sudo -n cat "$1" 2>/dev/null || cat "$1" 2>/dev/null; }
_ossl() { sudo -n openssl "$@" 2>/dev/null || openssl "$@" 2>/dev/null; }
while IFS= read -r F; do
  echo "=== $F ==="
  low=$(printf '%s' "$F" | tr 'A-Z' 'a-z')
  case "$low" in
    *.ks|*.jks|*.p12|*.pfx)
      echo "  Kind    : Java keystore"
      OUT=$( { sudo -n "$KT" -list -v -keystore "$F" -storepass __PASS__ 2>&1 || "$KT" -list -v -keystore "$F" -storepass __PASS__ 2>&1; } | grep -Ei 'Alias name|Owner|Issuer|Valid|SHA' )
      if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; else echo "  keystore: could not read (wrong password?)"; fi
      echo ""; continue ;;
  esac
  HDR=$(_read "$F" | grep -m1 -oE 'BEGIN [A-Z0-9 ]+' | sed 's/^BEGIN //')
  case "$HDR" in
    *CERTIFICATE" "REQUEST|*NEW" "CERTIFICATE" "REQUEST)
      echo "  Kind    : Certificate request (CSR)"
      OUT=$(_ossl req -in "$F" -noout -subject); if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; else echo "  (CSR could not be parsed)"; fi ;;
    *CERTIFICATE)
      echo "  Kind    : Certificate (X.509, PEM)"
      OUT=$(_ossl x509 -in "$F" -noout -subject -issuer -enddate -fingerprint -sha256)
      if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; else echo "  (certificate could not be parsed)"; fi ;;
    *PRIVATE" "KEY)
      echo "  Kind    : Private key (not a certificate - keys have no expiry)"
      SZ=$(_ossl pkey -in "$F" -pubout -passin pass: </dev/null | openssl pkey -pubin -noout -text 2>/dev/null | grep -iE '[0-9]+ bit' | head -1 | sed 's/^ *//')
      if [ -n "$SZ" ]; then echo "  Details : $SZ"; else echo "  Details : readable key (encrypted, or size not determined)"; fi ;;
    *PUBLIC" "KEY)
      echo "  Kind    : Public key"
      SZ=$(_ossl pkey -pubin -in "$F" -noout -text | grep -iE '[0-9]+ bit' | head -1 | sed 's/^ *//')
      [ -n "$SZ" ] && echo "  Details : $SZ" ;;
    *)
      OUT=$(_ossl x509 -inform der -in "$F" -noout -subject -issuer -enddate -fingerprint -sha256)
      if [ -n "$OUT" ]; then echo "  Kind    : Certificate (X.509, DER)"; printf '%s\n' "$OUT";
      else
        FT=$( { sudo -n file -b "$F" 2>/dev/null || file -b "$F" 2>/dev/null; } )
        echo "  Kind    : ${FT:-file (type unknown)}"
        SZ=$( { sudo -n stat -c '%s bytes' "$F" 2>/dev/null || stat -c '%s bytes' "$F" 2>/dev/null; } )
        [ -n "$SZ" ] && echo "  Details : $SZ"
        case "$low" in
          *.lic)
            PV=$(_read "$F" | tr -d '\r' | grep -m3 -v '^[[:space:]]*$')
            if [ -n "$PV" ]; then echo "  Preview :"; printf '%s\n' "$PV" | sed 's/^/    /'; fi ;;
        esac
      fi ;;
  esac
  echo ""
done < "$LIST"
rm -f "$LIST"
'@
    $cmd = $tmpl.Replace('__PATH__', (ConvertTo-OneLinkBashArg $Path)).Replace('__NAMEEXPR__', $NameExpr).Replace('__PASS__', (ConvertTo-OneLinkBashArg $KeystorePass))
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)
    return (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
}

# List files: scan the folder on the first selected server and fill the dropdown.
$BtnCertList.Add_Click({
    $targets = @(Get-OneLinkTargetHosts -Key 'Cert')
    if ($targets.Count -eq 0) { Show-ErrorMessage "Select a target server (and Connect) first."; return }
    $path = ([string]$TxtCertScanPath.Text).Trim(); if ($path -eq '') { $path = '/opt/onelink/etc/' }
    if ($path -notmatch '^/') { Show-ErrorMessage "Enter an absolute Linux path (starting with '/')."; return }
    $exts = Get-OneLinkCertExts (Get-ComboText $CmbCertType)
    $nameExpr = ($exts | ForEach-Object { "-iname '*.$_'" }) -join ' -o '
    $srv = $targets[0]
    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $files = @(Get-OneLinkCertFileList -Session $srv.Session -Settings $script:Settings -Path $path -NameExpr $nameExpr)
        $CmbCertFound.Items.Clear()
        if ($files.Count -eq 1 -and $files[0] -eq '__NOPATH__') { Show-WarningMessage "Path not found on $($srv.Host): $path"; return }
        if ($files.Count -eq 1 -and $files[0] -eq '__DENIED__') { Show-WarningMessage "Permission denied reading '$path' on $($srv.Host).`n`nThe folder is restricted and $($script:AppName) could not read it even with sudo (the account may lack passwordless sudo). Grant access, or check the path."; return }
        if ($files.Count -eq 0) { Show-WarningMessage "No matching files found in '$path' on $($srv.Host) (type: $(Get-ComboText $CmbCertType))."; return }
        foreach ($f in $files) { [void]$CmbCertFound.Items.Add($f) }
        $CmbCertFound.SelectedIndex = 0
        Write-OneLinkLog "[$($srv.Host)] Found $($files.Count) file(s) in $path." -Level Info
    }
    catch { Show-ErrorMessage "List failed on $($srv.Host). $($_.Exception.Message)" }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
})

$BtnCertStatus.Add_Click({
    $targets = @(Get-OneLinkTargetHosts -Key 'Cert')
    if ($targets.Count -eq 0) { Show-ErrorMessage "Select a target server (and Connect) first."; return }

    # The file to inspect: the one picked in 'Found files', else a full file path
    # typed in the scan box (not a folder).
    $file = ([string](Get-ComboText $CmbCertFound)).Trim()
    if ($file -eq '') {
        $p = ([string]$TxtCertScanPath.Text).Trim()
        if ($p -ne '' -and $p -notmatch '/$') { $file = $p }
    }
    if ($file -eq '') { Show-ErrorMessage "Click 'List files' and pick a file under 'Found files' - or type a full file path in the box above."; return }
    if ($file -notmatch '^/') { Show-ErrorMessage "The file path must be absolute (start with '/')."; return }

    $isKs = [bool]($file -match '(?i)\.(ks|jks|p12|pfx)$')
    $kind = if ($isKs) { 'Java keystore' } elseif ($file -match '(?i)\.lic$') { 'License' } elseif ($file -match '(?i)\.(pem|crt|cer|der|cert|ca)$') { 'Certificate' } else { 'File' }
    $ksPass = 'onelink'
    if ($isKs) {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $pp = [Microsoft.VisualBasic.Interaction]::InputBox("Keystore password for:`n$file`n`n(OneLink's default is 'onelink')", "Keystore Password", "onelink")
        if (-not [string]::IsNullOrEmpty($pp)) { $ksPass = $pp }
    }

    $script:Window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        $report = New-Object System.Collections.Generic.List[string]
        $report.Add("File : $file")
        $report.Add("Type : $kind")
        $report.Add('')
        foreach ($server in $targets) {
            $report.Add("--------------------------------------------------------------")
            $report.Add("Server : $($server.Host)")
            try {
                $text = Get-OneLinkCertScan -Session $server.Session -Settings $script:Settings -Path $file -NameExpr "-iname '*'" -KeystorePass $ksPass
                if ($text -match 'OLK_SCAN_NOPATH') { $report.Add("  Not found on this server.") }
                else { $report.Add((Format-OneLinkCertBlock $text)) }
                Write-OneLinkLog "[$($server.Host)] checked cert/license: $file" -Level Info
            }
            catch { $report.Add("  Error: $($_.Exception.Message)") }
            $report.Add('')
        }
        Show-OneLinkReport -Title "Certificate / License Status" -Body (($report -join [Environment]::NewLine)).TrimEnd()
    }
    finally { $script:Window.Cursor = [Windows.Input.Cursors]::Arrow }
})

