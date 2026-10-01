# ============================================================================
#  EMBEDDED MODULE: SshManager  (was Modules\SshManager.psm1)
# ============================================================================

function New-OneLinkCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][System.Security.SecureString]$Password
    )

    return [PSCredential]::new($Username, $Password)
}

function Connect-OneLinkSsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [Parameter(Mandatory)]$Settings
    )

    Import-OneLinkPoshSsh

    $params = @{
        ComputerName = $ComputerName
        Port = $Port
        Credential = $Credential
        ConnectionTimeout = [int]$Settings.Ssh.ConnectionTimeoutSeconds
        ErrorAction = 'Stop'
    }

    if ([bool]$Settings.Ssh.AcceptNewHostKey) {
        $params.AcceptKey = $true
    }

    try {
        return New-SSHSession @params
    }
    catch {
        # A rebuilt server presents a NEW SSH host key. Posh-SSH's -AcceptKey
        # trusts a brand-new host automatically, but REJECTS a *changed* key -
        # which SSH.NET reports as the misleading "Key exchange negotiation
        # failed". When we already have a stored key for this host AND the
        # failure looks like a host-key/KEX rejection, the server was almost
        # certainly rebuilt: refresh the stored key (the tool's equivalent of
        # 'ssh-keygen -R <host>') and retry ONCE. Auth/network errors do NOT
        # match this, so a wrong password never causes a key to be re-trusted.
        $trustChanged = [bool](Get-OneLinkProperty -Object $Settings.Ssh -Name 'TrustChangedHostKey' -Default $true)
        $cat = (Get-OneLinkFriendlySshError $_.Exception.Message).Category
        $hasStored = $false
        try { $hasStored = @(Get-SSHTrustedHost -HostName $ComputerName -ErrorAction SilentlyContinue).Count -gt 0 } catch { }
        if ($trustChanged -and $hasStored -and ($cat -eq 'KeyExchange' -or $cat -eq 'HostKey')) {
            Write-OneLinkLog "[$ComputerName] The server's SSH host key has changed since it was last trusted (the server was likely rebuilt). Refreshing the stored key and retrying." -Level Warning
            try { Remove-SSHTrustedHost -HostName $ComputerName -ErrorAction SilentlyContinue | Out-Null } catch { }
            return New-SSHSession @params
        }
        throw
    }
}

function Test-OneLinkSshConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [int]$TimeoutSeconds = 20
    )

    $result = Invoke-SSHCommand -SessionId $Session.SessionId `
        -Command "printf 'CONNECTED|'; hostname; printf '|'; id -un; printf '|'; uname -srm" `
        -TimeOut $TimeoutSeconds

    if ($result.ExitStatus -ne 0) {
        throw "SSH validation failed: $($result.Error -join [Environment]::NewLine)"
    }

    return ($result.Output -join [Environment]::NewLine)
}

# Turn a raw SSH/network exception into a short, plain-language reason a
# non-technical user can act on. Returns @{ Short = <grid status text>;
# Hint = <one-line suggestion for the log> }. Unknown errors pass through as-is.
function Get-OneLinkFriendlySshError {
    [CmdletBinding()]
    param([string]$Message)

    $m = [string]$Message
    switch -Regex ($m) {
        'key exchange|\bkex\b|negotiat' {
            return @{
                Category = 'KeyExchange'
                Short = 'incompatible SSH security settings (key exchange).'
                Hint  = "This usually means the server's SSH host key changed (e.g. it was rebuilt) and the old key is still trusted, OR the server offers handshake algorithms this tool's SSH library doesn't support. It is NOT a wrong-password issue and is unrelated to the Windows known_hosts file."
            }
        }
        'host key|hostkey|known.?host|fingerprint|server.?identif' {
            return @{
                Category = 'HostKey'
                Short = "server identity (host key) changed or rejected."
                Hint  = "The server's SSH host key has changed since it was last trusted (e.g. the box was rebuilt). If you trust this server, disconnect and reconnect to accept the new key."
            }
        }
        'denied|authenticat|permission|bad password|wrong password|credential|logon|login failed' {
            return @{
                Category = 'Auth'
                Short = 'username or password not accepted.'
                Hint  = 'Check the Username and Password cells for this row.'
            }
        }
        'timed out|timeout|actively refused|connection refused|unreachable|no such host|not known|could not resolve|no route|failed to establish' {
            return @{
                Category = 'Network'
                Short = "couldn't reach the server (check IP/host, port and network/VPN)."
                Hint  = 'Verify the server is powered on, the IP/host and port are correct, and you are on the right network/VPN.'
            }
        }
        default {
            return @{ Category = 'Other'; Short = $m; Hint = '' }
        }
    }
}

function Invoke-OneLinkSshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutSeconds = 120
    )

    # PowerShell here-strings carry this file's CRLF line endings. Bash on the
    # remote end chokes on a stray \r (e.g. "set -o pipefail<CR>" is read as an
    # invalid option name, heredoc terminators no longer match, and identifiers
    # embedded in scripts pick up a trailing \r). Every caller of this function
    # funnels through here, so normalize once rather than at each call site.
    $lfCommand = $Command.Replace("`r`n", "`n").Replace("`r", "`n")

    $result = Invoke-SSHCommand -SessionId $Session.SessionId -Command $lfCommand -TimeOut $TimeoutSeconds

    [PSCustomObject]@{
        ExitStatus = $result.ExitStatus
        Output = ($result.Output -join [Environment]::NewLine)
        Error = ($result.Error -join [Environment]::NewLine)
    }
}

function New-OneLinkShellStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings
    )

    # Posh-SSH 3.x exposes the terminal size as -Columns / -Rows (character
    # grid). The Settings.Ssh.TerminalWidth / TerminalHeight values are the
    # column and row counts, so they map directly onto those parameters.
    return New-SSHShellStream `
        -SessionId $Session.SessionId `
        -TerminalName ([string]$Settings.Ssh.TerminalName) `
        -Columns ([int]$Settings.Ssh.TerminalWidth) `
        -Rows ([int]$Settings.Ssh.TerminalHeight) `
        -BufferSize ([int]$Settings.Ssh.BufferSize)
}

function Disconnect-OneLinkSsh {
    [CmdletBinding()]
    param([AllowNull()]$Session)

    if ($null -ne $Session) {
        Remove-SSHSession -SessionId $Session.SessionId | Out-Null
    }
}

