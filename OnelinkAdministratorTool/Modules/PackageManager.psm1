Set-StrictMode -Version Latest

function Ensure-OneLinkRemoteDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$RemoteDirectory,
        [int]$TimeoutSeconds = 60
    )

    $quoted = "'" + ($RemoteDirectory -replace "'", "'\''") + "'"
    $result = Invoke-OneLinkSshCommand -Session $Session -Command "mkdir -p $quoted" -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitStatus -ne 0) {
        throw "Unable to create remote directory '$RemoteDirectory'. $($result.Error)"
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

    Import-Module Posh-SSH -ErrorAction Stop

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

function Install-OneLinkRpm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$RemotePackagePath,
        [ValidateSet('Install','Upgrade')][string]$Mode
    )

    $escapedPath = $RemotePackagePath.Replace("'", "'\''")
    $template = if ($Mode -eq 'Install') {
        [string]$Settings.Packages.InstallCommand
    } else {
        [string]$Settings.Packages.UpgradeCommand
    }

    $command = $template -f $escapedPath
    $result = Invoke-OneLinkSshCommand `
        -Session $Session `
        -Command $command `
        -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds)

    if ($result.ExitStatus -ne 0) {
        throw "RPM $Mode operation failed. $($result.Error) $($result.Output)"
    }

    return $result.Output
}

Export-ModuleMember -Function Ensure-OneLinkRemoteDirectory, Send-OneLinkPackage, Install-OneLinkRpm