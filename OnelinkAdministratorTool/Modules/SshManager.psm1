Set-StrictMode -Version Latest

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

    Import-Module Posh-SSH -ErrorAction Stop

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

    return New-SSHSession @params
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

function Invoke-OneLinkSshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutSeconds = 120
    )

    $result = Invoke-SSHCommand -SessionId $Session.SessionId -Command $Command -TimeOut $TimeoutSeconds

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

    return New-SSHShellStream `
        -SessionId $Session.SessionId `
        -TerminalName ([string]$Settings.Ssh.TerminalName) `
        -TerminalWidth ([int]$Settings.Ssh.TerminalWidth) `
        -TerminalHeight ([int]$Settings.Ssh.TerminalHeight) `
        -BufferSize ([int]$Settings.Ssh.BufferSize)
}

function Disconnect-OneLinkSsh {
    [CmdletBinding()]
    param([AllowNull()]$Session)

    if ($null -ne $Session) {
        Remove-SSHSession -SessionId $Session.SessionId | Out-Null
    }
}

Export-ModuleMember -Function New-OneLinkCredential, Connect-OneLinkSsh, Test-OneLinkSshConnection, Invoke-OneLinkSshCommand, New-OneLinkShellStream, Disconnect-OneLinkSsh