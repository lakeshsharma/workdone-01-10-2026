# Browse for a LOCAL Windows backup file (only relevant to the 'Local Windows' location).
# MAXIMUM time (seconds) a backup/restore SSH command is ALLOWED to run before the
# tool gives up - it is a ceiling, NOT a fixed wait: the command returns the instant
# it finishes. Default 129600 = 36 hours (1.5 days) for very large dumps; override
# via Settings.json -> Database.BackupTimeoutSeconds.
$script:BackupTimeoutSeconds = 129600
try { if ($script:Settings.Database -and $script:Settings.Database.BackupTimeoutSeconds) { $script:BackupTimeoutSeconds = [int]$script:Settings.Database.BackupTimeoutSeconds } } catch { }

# Last path segment, treating both / and \ as separators (Linux or Windows/UNC).
function Get-OneLinkPathLeaf { param([string]$Path) return (($Path -split '[\\/]') | Where-Object { $_ -ne '' } | Select-Object -Last 1) }

# --- Backup (Export) file picker + destination toggles ---
$BtnBrowseExport.Add_Click({
    if ((Get-ComboText $CmbExportDest) -notlike 'Local*') {
        Show-InfoMessage "Browse is for 'Local Windows' files. For 'Server' type a Linux path; for 'Network location' type a UNC path (e.g. \\server\share\db.sql.gz)."
        return
    }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'SQL backups (*.sql;*.gz;*.zip)|*.sql;*.gz;*.zip|All files (*.*)|*.*'
    $dlg.CheckFileExists = $false   # naming a NEW file for the backup
    $dlg.Title = 'Name the backup file on this PC'
    try { if (-not [string]::IsNullOrWhiteSpace($TxtExportFile.Text)) { $dlg.InitialDirectory = [IO.Path]::GetDirectoryName($TxtExportFile.Text); $dlg.FileName = [IO.Path]::GetFileName($TxtExportFile.Text) } } catch { }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $TxtExportFile.Text = $dlg.FileName }
})

$CmbExportDest.Add_SelectionChanged({
    $loc = Get-ComboText $CmbExportDest
    $ExportNetRow.Visibility = if ($loc -like 'Network*') { 'Visible' } else { 'Collapsed' }
    if ($loc -like 'Local*' -and $TxtExportFile.Text -match '^/') { $TxtExportFile.Text = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'onelink_db_export.sql.gz') }
    elseif ($loc -like 'Network*' -and $TxtExportFile.Text -notmatch '^\\\\') { $TxtExportFile.Text = '\\server\share\onelink_db_export.sql.gz' }
    elseif ($loc -like 'Server*' -and $TxtExportFile.Text -notmatch '^/') { $TxtExportFile.Text = '/mysqldata/ndb_export.sql.gz' }
})

# --- Restore (Import) file picker + source toggles ---
$BtnBrowseImport.Add_Click({
    if ((Get-ComboText $CmbImportSrc) -notlike 'Local*') {
        Show-InfoMessage "Browse is for 'Local Windows' files. For 'Server' / 'Another VM' type a Linux path; for 'Network location' type a UNC path."
        return
    }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'SQL backups (*.sql;*.gz;*.zip)|*.sql;*.gz;*.zip|All files (*.*)|*.*'
    $dlg.CheckFileExists = $true    # the backup to restore must exist
    $dlg.Title = 'Select the backup file on this PC'
    try { if (-not [string]::IsNullOrWhiteSpace($TxtImportFile.Text)) { $dlg.InitialDirectory = [IO.Path]::GetDirectoryName($TxtImportFile.Text); $dlg.FileName = [IO.Path]::GetFileName($TxtImportFile.Text) } } catch { }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $TxtImportFile.Text = $dlg.FileName }
})

$CmbImportSrc.Add_SelectionChanged({
    $loc = Get-ComboText $CmbImportSrc
    $ImportNetRow.Visibility = if ($loc -like 'Network*') { 'Visible' } else { 'Collapsed' }
    $ImportVmRow.Visibility  = if ($loc -like 'Another VM*') { 'Visible' } else { 'Collapsed' }
    if ($loc -like 'Local*' -and $TxtImportFile.Text -match '^/') { $TxtImportFile.Text = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'onelink_db_export.sql.gz') }
    elseif ($loc -like 'Network*' -and $TxtImportFile.Text -notmatch '^\\\\') { $TxtImportFile.Text = '\\server\share\onelink_db_export.sql.gz' }
    elseif (($loc -like 'Server*' -or $loc -like 'Another VM*') -and $TxtImportFile.Text -notmatch '^/') { $TxtImportFile.Text = '/mysqldata/ndb_export.sql.gz' }
})

