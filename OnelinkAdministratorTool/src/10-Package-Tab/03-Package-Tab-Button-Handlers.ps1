$BtnBrowsePackage.Add_Click({
    # Pre-check whatever's already in the box (each ';'-separated segment that's a
    # real local folder) so reopening the picker shows the current selection ticked.
    $existing = @(([string]$TxtPackagePath.Text) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^\\\\' -and (Test-Path -LiteralPath $_ -PathType Container) })
    $picked = Show-OneLinkMultiFolderPicker -InitialSelection $existing
    if ($null -ne $picked -and $picked.Count -gt 0) {
        $TxtPackagePath.Text = ($picked -join ' ; ')
    }
})

# Network-login fields are faded until the user ticks the checkbox.
$ChkPkgNetAuth.Add_Click({
    $on = [bool]$ChkPkgNetAuth.IsChecked
    $TxtNetUser.IsEnabled = $on; $PwdNetPass.IsEnabled = $on; $BtnPkgNetTest.IsEnabled = $on
    if (-not $on) { $TxtNetUser.Text = '' }
})

$BtnBuildPlan.Add_Click({ Build-OneLinkPackagePlan })

# NOTE: the Size column is filled when the plan is built (Build-OneLinkPackagePlan).
# We deliberately do NOT refresh it from the ComboBox SelectionChanged event: doing
# so calls Items.Refresh(), which re-fires SelectionChanged and loops forever,
# freezing the UI. If the user changes a package, they can click Build / Refresh
# Plan to update sizes. (No grid refresh from a selection event = no reentrancy.)

$BtnRemovePlanRow.Add_Click({
    $selected = @($PackageGrid.SelectedItems)
    if ($selected.Count -eq 0) {
        Show-ErrorMessage "Select one or more plan rows to remove."
        return
    }
    foreach ($row in $selected) { [void]$script:PackagePlan.Remove($row) }
    Invoke-GridRefresh $PackageGrid
    Write-OneLinkLog "Removed $($selected.Count) row(s) from the deployment plan." -Level Info
})

$BtnClearPlan.Add_Click({
    if ($script:PackagePlan.Count -eq 0) { return }
    $script:PackagePlan.Clear()
    Invoke-GridRefresh $PackageGrid
    Write-OneLinkLog "Deployment plan cleared." -Level Info
})

$BtnUploadPackage.Add_Click({ Invoke-OneLinkPackageDeployment -Install:$false })

$BtnUploadInstall.Add_Click({ Invoke-OneLinkPackageDeployment -Install:$true })

# (The Service target picker rebuilds the checklist itself when its ticks change.)
$BtnRefreshServices.Add_Click({
    # Force a re-scan of auxiliary (non-OneLink) units on the target(s) so a
    # newly-installed app service shows up, then rebuild the checklist.
    foreach ($server in @(Get-OneLinkTargetHosts -Key 'Service')) {
        Update-OneLinkAuxServices -Server $server -Force
    }
    Update-ServiceChecklist
})

$TxtServiceSearch.Add_TextChanged({ Update-OneLinkServiceFilter })
$BtnSvcSelectAll.Add_Click({ Set-OneLinkServicesChecked -Checked $true })
$BtnSvcDeselectAll.Add_Click({ Set-OneLinkServicesChecked -Checked $false })

