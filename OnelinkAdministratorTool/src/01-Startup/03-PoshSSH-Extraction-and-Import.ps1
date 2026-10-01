function Initialize-EmbeddedPoshSsh {
    [CmdletBinding()]
    param()

    # Prefer a Posh-SSH already available on the machine.
    if (Get-Module -ListAvailable -Name Posh-SSH -ErrorAction SilentlyContinue) { return }

    if ([string]::IsNullOrWhiteSpace($script:PoshSshZipBase64) -or
        $script:PoshSshZipBase64.Trim().Length -lt 100000) {
        throw "Posh-SSH is not installed on this machine and no embedded copy was compiled into this build."
    }

    $modulesRoot = Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\Modules'
    $moduleDir   = Join-Path $modulesRoot ("Posh-SSH\" + $script:PoshSshEmbeddedVersion)
    $manifest    = Join-Path $moduleDir 'Posh-SSH.psd1'

    if (-not (Test-Path -LiteralPath $manifest)) {
        if (Test-Path -LiteralPath $moduleDir) {
            Remove-Item -LiteralPath $moduleDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null

        $tempZip = Join-Path $env:TEMP ("PoshSSH_" + [Guid]::NewGuid().ToString('N') + ".zip")
        try {
            [IO.File]::WriteAllBytes($tempZip, [Convert]::FromBase64String($script:PoshSshZipBase64.Trim()))
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $moduleDir)
        }
        finally {
            if (Test-Path -LiteralPath $tempZip) {
                Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Make 'Import-Module Posh-SSH' resolve to the extracted copy.
    if (($env:PSModulePath -split ';') -notcontains $modulesRoot) {
        $env:PSModulePath = $modulesRoot + ';' + $env:PSModulePath
    }
}

# Ensure Posh-SSH is loaded (from the machine, or the embedded copy).
function Import-OneLinkPoshSsh {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name Posh-SSH)) {
        Initialize-EmbeddedPoshSsh
        Import-Module Posh-SSH -ErrorAction Stop
    }
}

