Set-StrictMode -Version Latest

function Read-OneLinkShellAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ShellStream)

    $text = ""
    while ($ShellStream.DataAvailable) {
        $text += $ShellStream.Read()
        Start-Sleep -Milliseconds 50
    }
    return $text
}

function Wait-OneLinkShellPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutSeconds = 45,
        [string]$FailurePattern = '(?i)(failed|error|invalid|denied)'
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $buffer = ""

    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($ShellStream.DataAvailable) {
            $buffer += $ShellStream.Read()

            if ($FailurePattern -and $buffer -match $FailurePattern) {
                throw "Remote operation reported a failure. Output: $buffer"
            }

            if ($buffer -match $Pattern) {
                return $buffer
            }
        }
        Start-Sleep -Milliseconds 150
    }

    throw "Timed out after $TimeoutSeconds seconds while waiting for pattern '$Pattern'. Last output: $buffer"
}

function Send-OneLinkShellValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [AllowEmptyString()][string]$Value,
        [switch]$Sensitive
    )

    $ShellStream.WriteLine($Value)
    if ($Sensitive) {
        Write-OneLinkLog "Sent protected input to the remote prompt." -Level Debug
    }
    else {
        Write-OneLinkLog "Sent value '$Value' to the remote prompt." -Level Debug
    }
}

function Start-OneLinkNMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings
    )

    $command = [string]$Settings.Remote.NMenuCommand
    Write-OneLinkLog "Starting nmenu." -Level Info
    $ShellStream.WriteLine($command)
    return Wait-OneLinkShellPattern `
        -ShellStream $ShellStream `
        -Pattern ([string]$Mappings.Common.MainMenuPrompt) `
        -TimeoutSeconds ([int]$Settings.Ssh.PromptTimeoutSeconds) `
        -FailurePattern ([string]$Mappings.Common.GenericFailure)
}

function Complete-OneLinkNMenuOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$SuccessPattern
    )

    $result = Wait-OneLinkShellPattern `
        -ShellStream $ShellStream `
        -Pattern $SuccessPattern `
        -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds) `
        -FailurePattern ([string]$Mappings.Common.GenericFailure)

    Start-Sleep -Milliseconds 300
    $remaining = Read-OneLinkShellAvailable -ShellStream $ShellStream
    $combined = $result + $remaining

    if ($combined -match [string]$Mappings.Common.ContinuePrompt) {
        $ShellStream.WriteLine("")
    }

    return $combined
}

function Invoke-NMenuCreateDatabaseUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [AllowEmptyString()][string]$AllowedIp
    )

    Start-OneLinkNMenu -ShellStream $ShellStream -Settings $Settings -Mappings $Mappings | Out-Null

    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.MainMenuKey)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.SubMenuPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.CreateUser.Key)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.CreateUser.UsernamePrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $Username
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.CreateUser.PasswordPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $Password -Sensitive
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.CreateUser.IpPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $AllowedIp
    return Complete-OneLinkNMenuOperation $ShellStream $Settings $Mappings ([string]$Mappings.Database.CreateUser.SuccessPrompt)
}

function Invoke-NMenuCreateDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$DatabaseName
    )

    Start-OneLinkNMenu $ShellStream $Settings $Mappings | Out-Null
    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.MainMenuKey)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.SubMenuPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.CreateDatabase.Key)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.CreateDatabase.DatabasePrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $DatabaseName
    return Complete-OneLinkNMenuOperation $ShellStream $Settings $Mappings ([string]$Mappings.Database.CreateDatabase.SuccessPrompt)
}

function Invoke-NMenuGrantPrivileges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$AllowedIp,
        [Parameter(Mandatory)][string]$DatabaseName,
        [Parameter(Mandatory)][string]$Password
    )

    Start-OneLinkNMenu $ShellStream $Settings $Mappings | Out-Null
    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.MainMenuKey)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.SubMenuPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Database.GrantPrivileges.Key)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.GrantPrivileges.UsernamePrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $Username
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.GrantPrivileges.IpPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $AllowedIp
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.GrantPrivileges.DatabasePrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $DatabaseName
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Database.GrantPrivileges.PasswordPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $Password -Sensitive
    return Complete-OneLinkNMenuOperation $ShellStream $Settings $Mappings ([string]$Mappings.Database.GrantPrivileges.SuccessPrompt)
}

function Invoke-NMenuServiceAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$ServiceDisplayName,
        [ValidateSet('Start','Restart')][string]$Action
    )

    $serviceKey = [string]$Mappings.Services.ServiceKeys.$ServiceDisplayName
    $actionKey = [string]$Mappings.Services.ActionKeys.$Action

    if (-not $serviceKey) { throw "No nmenu key is configured for service '$ServiceDisplayName'." }
    if (-not $actionKey) { throw "No nmenu key is configured for action '$Action'." }

    Start-OneLinkNMenu $ShellStream $Settings $Mappings | Out-Null
    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Services.MainMenuKey)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Services.SubMenuPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $serviceKey
    Start-Sleep -Milliseconds 400
    Send-OneLinkShellValue $ShellStream $actionKey

    return Complete-OneLinkNMenuOperation $ShellStream $Settings $Mappings ([string]$Mappings.Services.SuccessPrompt)
}

function Invoke-NMenuEnableSsl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ShellStream,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)][string]$Component
    )

    $componentKey = [string]$Mappings.Ssl.ComponentKeys.$Component
    if (-not $componentKey) { throw "No SSL menu key is configured for '$Component'." }

    Start-OneLinkNMenu $ShellStream $Settings $Mappings | Out-Null
    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Ssl.MainMenuKey)
    Wait-OneLinkShellPattern $ShellStream ([string]$Mappings.Ssl.SubMenuPrompt) ([int]$Settings.Ssh.PromptTimeoutSeconds) | Out-Null

    Send-OneLinkShellValue $ShellStream $componentKey
    Start-Sleep -Milliseconds 400
    Send-OneLinkShellValue $ShellStream ([string]$Mappings.Ssl.EnableKey)

    return Complete-OneLinkNMenuOperation $ShellStream $Settings $Mappings ([string]$Mappings.Ssl.SuccessPrompt)
}

Export-ModuleMember -Function Read-OneLinkShellAvailable, Wait-OneLinkShellPattern, Send-OneLinkShellValue, Start-OneLinkNMenu, Complete-OneLinkNMenuOperation, Invoke-NMenuCreateDatabaseUser, Invoke-NMenuCreateDatabase, Invoke-NMenuGrantPrivileges, Invoke-NMenuServiceAction, Invoke-NMenuEnableSsl