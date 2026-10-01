function Get-ComboText {
    param($ComboBox)
    if ($null -eq $ComboBox.SelectedItem) { return "" }
    if ($ComboBox.SelectedItem.PSObject.Properties.Name -contains 'Content') {
        return [string]$ComboBox.SelectedItem.Content
    }
    return [string]$ComboBox.SelectedItem
}

# Decrypt a SecureString to plain text (used only to pre-fill / reveal a stored
# password in the Set-Password dialog; the value stays in memory for this session).
function ConvertFrom-OneLinkSecure {
    param([AllowNull()]$Secure)
    if ($null -eq $Secure -or $Secure.Length -eq 0) { return '' }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Safely refresh a DataGrid. A DataGrid throws "Refresh is not allowed during an
# AddNew or EditItem transaction" if a cell/row is mid-edit, so commit any
# pending edit first. All calls are guarded so a refresh can never surface an
# exception to the user.
function Invoke-GridRefresh {
    param($Grid)
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) } catch { }
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) }  catch { }
    try { $Grid.Items.Refresh() } catch { }
}

# Startup self-check for the embedded Posh-SSH module. This runs on EVERY launch
# and validates the blob REGARDLESS of whether this machine already has Posh-SSH
# installed - so an incomplete build (compiled without the embedded module) is
# caught immediately on the builder's own machine, instead of only failing later
# on a clean machine that has no Posh-SSH to fall back on.
function Confirm-OneLinkPoshSsh {
    $b = $script:PoshSshZipBase64
    # A real blob is a large base64 string; the un-injected placeholder is tiny.
    $embeddedOk = (-not [string]::IsNullOrWhiteSpace($b)) -and ($b.Trim().Length -ge 100000)
    $machineHas = [bool](Get-Module -ListAvailable -Name Posh-SSH -ErrorAction SilentlyContinue)

    if (-not $embeddedOk) {
        $msg = "INCOMPLETE BUILD: this EXE was compiled WITHOUT the embedded Posh-SSH module." + [Environment]::NewLine +
               "It may work on machines that already have Posh-SSH installed, but it WILL FAIL on a clean machine." + [Environment]::NewLine + [Environment]::NewLine +
               "Rebuild from the full source - run Build.ps1 (recommended)."
        Write-OneLinkLog "INCOMPLETE BUILD: embedded Posh-SSH module is missing from this EXE. Rebuild with Build.ps1." -Level Error
        [System.Windows.MessageBox]::Show($msg, "$($script:AppName) - incomplete build", 'OK', 'Warning') | Out-Null
        return
    }

    if ($machineHas) {
        Write-OneLinkLog "Posh-SSH is present on this machine (embedded copy verified as a fallback)." -Level Info
        return
    }

    # Clean machine: prepare the bundled copy now so any problem shows at launch.
    # Detect whether this is the FIRST time (manifest not yet extracted) so we can
    # show a one-time, per-machine "dependency set up" notice.
    $modulesRoot = Join-Path $env:LOCALAPPDATA 'OneLinkAdminTool\Modules'
    $manifest = Join-Path $modulesRoot ("Posh-SSH\" + $script:PoshSshEmbeddedVersion + "\Posh-SSH.psd1")
    $firstRun = -not (Test-Path -LiteralPath $manifest)

    try {
        Initialize-EmbeddedPoshSsh
        if ($firstRun) {
            Write-OneLinkLog "First-run setup: bundled Posh-SSH extracted to $modulesRoot (per-user, no admin)." -Level Success
            [System.Windows.MessageBox]::Show(
                "First-time setup complete." + [Environment]::NewLine + [Environment]::NewLine +
                "This tool needs the Posh-SSH component for SSH/SCP. It is bundled inside the application, so nothing has to be installed manually - it was just prepared for this machine (per-user folder, no admin rights, no internet required)." + [Environment]::NewLine + [Environment]::NewLine +
                "You won't see this message again on this machine.",
                "$($script:AppName) - dependency ready", 'OK', 'Information') | Out-Null
        }
        else {
            Write-OneLinkLog "Bundled Posh-SSH ready (already prepared on this machine)." -Level Info
        }
    }
    catch {
        Write-OneLinkLog "Bundled Posh-SSH preparation warning: $($_.Exception.Message)" -Level Warning
    }
}

