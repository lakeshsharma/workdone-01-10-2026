# ============================================================================
#  EMBEDDED MODULE: PackageManager  (was Modules\PackageManager.psm1)
# ============================================================================

function Ensure-OneLinkRemoteDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$RemoteDirectory,
        [int]$TimeoutSeconds = 60
    )

    $quoted = "'" + ($RemoteDirectory -replace "'", "'\''") + "'"
    # Create the upload dir AND make sure the SSH user can write to it. A common
    # failure is the dir being left root-owned by an earlier run, which makes the
    # SCP upload fail with "Permission denied". If it is not writable, recreate /
    # chown it to the connecting user via sudo, then verify.
    $cmd = @"
mkdir -p $quoted 2>/dev/null || true
# Take ownership of the dir AND every file inside it (recursive). A root-owned
# leftover file - from an earlier run or a manual 'sudo' copy - blocks the SCP
# overwrite with "Permission denied" even when the directory itself is writable.
sudo chown -R "`$(id -un)":"`$(id -gn)" $quoted 2>/dev/null || true
# Verify by actually creating a file (real write test, not just [ -w ]).
if touch $quoted/.olk_w 2>/dev/null; then rm -f $quoted/.olk_w 2>/dev/null; echo OLK_DIR_OK; else echo OLK_DIR_FAIL; fi
"@
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $cmd -TimeoutSeconds $TimeoutSeconds
    if (([string]$result.Output) -notmatch 'OLK_DIR_OK') {
        throw "Remote upload directory '$RemoteDirectory' is not writable by the SSH user and could not be fixed with sudo (the account may lack passwordless sudo). Fix its ownership on the server (e.g. sudo rm -rf '$RemoteDirectory'), or use a directory under the user's home."
    }
}

function Send-OneLinkPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemoteDirectory
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        throw "Package file was not found: $LocalPath"
    }

    Import-OneLinkPoshSsh

    Set-SCPItem `
        -ComputerName $ComputerName `
        -Port $Port `
        -Credential $Credential `
        -Path $LocalPath `
        -Destination $RemoteDirectory `
        -AcceptKey `
        -ErrorAction Stop

    return (Join-Path $RemoteDirectory ([IO.Path]::GetFileName($LocalPath))).Replace('\','/')
}

# Built-in command templates used when Settings.Packages.Types does not define
# a given extension (keeps older external Settings.json files working).
function Get-OneLinkDefaultPackageCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Extension,
        [Parameter(Mandatory)][string]$Mode
    )

    switch ($Extension) {
        'rpm' {
            if ($Mode -eq 'Install') { return "sudo rpm -ivh --replacepkgs '{0}'" }
            return "sudo rpm -Uvh '{0}'"
        }
        'deb' {
            # Return dpkg's own exit status; run the dependency fix best-effort
            # so an offline apt-get can never mask a successful dpkg install.
            return 'sudo DEBIAN_FRONTEND=noninteractive dpkg -i ''{0}''; rc=$?; sudo DEBIAN_FRONTEND=noninteractive apt-get -y -f install >/dev/null 2>&1 || true; exit $rc'
        }
        default {
            throw "Unsupported package type '.$Extension'. Add a template under Packages.Types.$Extension in Settings.json."
        }
    }
}

# Install/upgrade a package, auto-detecting the packager from the file
# extension (.rpm -> RHEL/rpm, .deb -> Debian/dpkg, others configurable via
# Settings.Packages.Types). Any interactive prompt is auto-answered (the
# configured Packages.AutoAnswer value is fed on repeat via 'yes', which also
# presses Enter for you) so installation runs unattended.
function Install-OneLinkPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$RemotePackagePath,
        [ValidateSet('Install','Upgrade')][string]$Mode,
        [AllowEmptyString()][string]$Reason = ''
    )

    $ext = ([IO.Path]::GetExtension($RemotePackagePath)).TrimStart('.').ToLowerInvariant()
    if ($ext -ne 'rpm' -and $ext -ne 'deb') {
        throw "Unsupported package type '.$ext' (only .rpm and .deb are supported)."
    }

    if ([string]::IsNullOrEmpty($Reason)) {
        $Reason = [string](Get-OneLinkProperty -Object $Settings.Packages -Name 'Reason' -Default "Installed via $($script:AppName)")
    }

    $pkgQ = ConvertTo-OneLinkBashArg $RemotePackagePath
    $reasonQ = ConvertTo-OneLinkBashArg $Reason

    # We do NOT trust the package-manager exit code (dpkg/rpm can return non-zero
    # for cosmetic reasons, e.g. a postinst warning). Instead we install, then
    # ask the package database whether the package - identified by the NAME read
    # FROM the file itself - is now present at the version we shipped. The REASON
    # is supplied both as an env var and on stdin (compliance prompt). No apt-get
    # / dnf dependency step is run.
    if ($ext -eq 'deb') {
        $template = @'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
set +e
PKGFILE=__PKGQ__
PKG=$(dpkg-deb -f "$PKGFILE" Package 2>/dev/null)
WANT=$(dpkg-deb -f "$PKGFILE" Version 2>/dev/null)
yes __REASONQ__ 2>/dev/null | head -n 200 | sudo env REASON=__REASONQ__ DEBIAN_FRONTEND=noninteractive dpkg -i "$PKGFILE"
STATUS=$(dpkg-query -W -f='${Status}' "$PKG" 2>/dev/null)
HAVE=$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null)
echo "OLK_VERIFY package=$PKG wanted=$WANT installed=$HAVE state=[$STATUS]"
if [ "$STATUS" = "install ok installed" ] && [ -n "$WANT" ] && [ "$HAVE" = "$WANT" ]; then echo "OLK_RESULT=OK"; else echo "OLK_RESULT=FAIL"; fi
'@
        $script = $template.Replace('__PKGQ__', $pkgQ).Replace('__REASONQ__', $reasonQ)
    }
    else {
        $rpmCmd = if ($Mode -eq 'Install') { 'rpm -ivh --replacepkgs' } else { 'rpm -Uvh' }
        # The OneLink RPM's %prein scriptlet prompts for a compliance reason by
        # reading /dev/tty. An SSH exec has no controlling terminal, so a plain
        # install dies with "/dev/tty: No such device or address". We run rpm
        # inside a pseudo-terminal via `script` so /dev/tty exists, and feed the
        # reason into that tty (also pass REASON as an env var, like the .deb path).
        $template = @'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
set +e
PKGFILE=__PKGQ__
PKG=$(rpm -qp --qf '%{NAME}' "$PKGFILE" 2>/dev/null)
WANT=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$PKGFILE" 2>/dev/null)
if command -v script >/dev/null 2>&1; then
  yes __REASONQ__ 2>/dev/null | head -n 200 | sudo env REASON=__REASONQ__ script -qe -c "__RPMCMD__ \"$PKGFILE\"" /dev/null
else
  yes __REASONQ__ 2>/dev/null | head -n 200 | sudo env REASON=__REASONQ__ __RPMCMD__ "$PKGFILE"
fi
HAVE=$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$PKG" 2>/dev/null)
echo "OLK_VERIFY package=$PKG wanted=$WANT installed=$HAVE"
if rpm -q "$PKG" >/dev/null 2>&1 && [ -n "$WANT" ] && [ "$HAVE" = "$WANT" ]; then echo "OLK_RESULT=OK"; else echo "OLK_RESULT=FAIL"; fi
'@
        $script = $template.Replace('__PKGQ__', $pkgQ).Replace('__REASONQ__', $reasonQ).Replace('__RPMCMD__', $rpmCmd)
    }

    # Package installs can be slow (large packages, scriptlets, service setup),
    # far longer than a normal command. Use a generous install timeout - the
    # configurable Packages.InstallTimeoutSeconds (default 1800s = 30 min),
    # never shorter than the normal command timeout.
    $installTimeout = [int](Get-OneLinkProperty -Object $Settings.Packages -Name 'InstallTimeoutSeconds' -Default 1800)
    if ($installTimeout -lt [int]$Settings.Ssh.CommandTimeoutSeconds) { $installTimeout = [int]$Settings.Ssh.CommandTimeoutSeconds }

    Write-OneLinkLog "Installing .$ext package ($Mode); success is verified against the package database (timeout ${installTimeout}s)." -Level Debug
    $result = Invoke-OneLinkSshCommand `
        -Session $Session `
        -Command $script `
        -TimeoutSeconds $installTimeout

    $output = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine

    if ($output -notmatch 'OLK_RESULT=OK') {
        throw "$ext $Mode did not verify as installed. $output"
    }

    # Return the package output without our internal marker line.
    return (($output -split "`r?`n" | Where-Object { $_ -notmatch '^OLK_RESULT=' }) -join [Environment]::NewLine)
}

