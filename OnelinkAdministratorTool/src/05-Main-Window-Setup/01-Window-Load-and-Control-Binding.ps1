# ============================================================================
#  RUNTIME BOOTSTRAP
# ============================================================================

# Load configuration: external file beside the EXE if present, else embedded.
$script:Settings = Get-OneLinkConfiguration `
    -ExternalPath (Join-Path $script:BaseDirectory 'Settings.json') `
    -DefaultJson $script:DefaultSettingsJson

$script:Mappings = Get-OneLinkConfiguration `
    -ExternalPath (Join-Path $script:BaseDirectory 'NMenuMappings.json') `
    -DefaultJson $script:DefaultMappingsJson

# Load the WPF window from the embedded XAML.
[xml]$xaml = $script:MainWindowXaml
$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:Window = [Windows.Markup.XamlReader]::Load($reader)

# Shrink only the INITIAL size to fit the usable screen area, so a centered
# window never opens with its title bar (minimize/maximize/close) off-screen.
# No MaxHeight/MaxWidth cap is set, so the window stays freely resizable and can
# still be maximized.
$workArea = [System.Windows.SystemParameters]::WorkArea
if ($script:Window.Height -gt ($workArea.Height - 20)) { $script:Window.Height = $workArea.Height - 20 }
if ($script:Window.Width  -gt $workArea.Width)         { $script:Window.Width  = $workArea.Width }


function Get-Control {
    param([Parameter(Mandatory)][string]$Name)
    $control = $script:Window.FindName($Name)
    if ($null -eq $control) { throw "Unable to find UI control '$Name'." }
    return $control
}

$uiNames = @(
    'TxtAppTitle','TxtAppFooter','TxtAppBadge',
    'BtnAddServer','BtnRemoveServer','BtnSameCreds','BtnTemplateConfig','BtnImportConfig','BtnExportConfig','ServerGrid',
    'BtnConnect','BtnDisconnect','TxtConnectionStatus',
    'BtnTargetDb','PnlTargetDb','BtnMysqlRestart','BtnMysqlStop','BtnMysqlStatus','TxtMysqlStatus','TxtDbUser','PwdDbUser','PwdDbUserConfirm','ChkSetAllowedIp','CmbDbUserIp','BtnCreateDbUser',
    'TxtDatabaseName','BtnCreateDatabase','CmbGrantUser','CmbGrantHost','CmbGrantDb','PwdGrant','PwdGrantConfirm','BtnRefreshDbLists','BtnGrantPrivileges',
    'TxtInnodbInfo','BtnInnodbCheck','TxtInnodbSize','BrdInnodbWarn','TxtInnodbWarn','BtnInnodbApply',
    'TxtSqlSearchTerm','BtnSqlSearch','CmbSqlScriptFound','BtnRunSqlScript','TxtSqlSearchStatus',
    'CmbExportDb','CmbExportDest','ExportNetRow','TxtExportNetUser','PwdExportNetPass','TxtExportFile','BtnBrowseExport','TxtExportStatus','BtnExportDb','BtnStopExport',
    'CmbImportDb','CmbImportSrc','ImportNetRow','TxtImportNetUser','PwdImportNetPass','ImportVmRow','TxtImportVmHost','TxtImportVmUser','PwdImportVmPass','TxtImportFile','BtnBrowseImport','TxtImportStatus','BtnImportDb','BtnStopImport',
    'TxtPackagePath','ChkPkgNetAuth','TxtNetUser','PwdNetPass','BtnPkgNetTest','BtnBrowsePackage','TxtRemoteDirectory','CmbInstallMode','TxtInstallReason','BtnBuildPlan','BtnRemovePlanRow','BtnClearPlan','PackageGrid','CmbSslAfterInstall','ChkEnableStart','BtnUploadPackage','BtnUploadInstall',
    'BtnTargetService','PnlTargetService','SvcCheckPanel','TxtServiceSearch','BtnSvcSelectAll','BtnSvcDeselectAll','BtnRefreshServices','CmbServiceAction','BtnServiceAction','BtnServiceStatus','BtnServiceDetails',
    'BtnTargetCert','PnlTargetCert','TxtCertFile','BtnBrowseCert','ChkCertNetAuth','TxtCertNetUser','PwdCertNetPass','BtnCertNetTest','TxtCertDest','CmbCertBackupDest','TxtCertBackupPath','BtnCertBackupBrowse','CmbCertType','TxtCertScanPath','BtnCertList','CmbCertFound','BtnDeployCert','BtnCertStatus',
    'TxtLog','BtnClearLog','BtnOpenLog',
    'TxtActivityHud','BtnUnlockMetrics','BtnLogFolder','BtnResetTool','OperationTabs','TabMetrics','ChkCaptureMetrics','ActivityGrid','TxtActivitySummary','BtnExportMetrics','BtnClearMetrics'
)

foreach ($name in $uiNames) {
    Set-Variable -Name $name -Value (Get-Control -Name $name) -Scope Script
}

# Apply the tool name (single source: $script:AppName) to the title bar, header
# and footer. Everything else uses $script:AppName directly.
$script:Window.Title = $script:AppName
$TxtAppTitle.Text = $script:AppName
$TxtAppFooter.Text = "$script:AppName $([char]0x00B7) $script:AppTagline"
$TxtAppBadge.Text = $script:AppTagline
# Title-bar / taskbar icon (vector, so it shows even when run from source).
try { $script:Window.Icon = [System.Windows.Media.ImageSource]($script:Window.FindResource('AppLogo')) } catch { }

