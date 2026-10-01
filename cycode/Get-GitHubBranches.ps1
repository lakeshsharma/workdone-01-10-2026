<#
.SYNOPSIS
    Lists ALL branches (including ones with zero Cycode violations) for a set of
    repos in a GitHub organization and writes a report (CSV + optional Excel).

.DESCRIPTION
    Prompts for a GitHub Personal Access Token (typed hidden, kept only in memory,
    never written to disk). Needs read access to the repos ("repo" scope for a
    classic token, or Contents:Read / Metadata:Read for a fine-grained token). If
    the org enforces SSO, authorize the token for the org first
    (GitHub > Settings > Developer settings > Tokens > Configure SSO).

.EXAMPLE
    .\Get-GitHubBranches.ps1
    .\Get-GitHubBranches.ps1 -OutputDir C:\Temp
    .\Get-GitHubBranches.ps1 -Repos cxs-olk-product-onelink,cxs-olk-product-mbox
#>
[CmdletBinding()]
param(
    [string]$Org = 'AristocratEnterprise',
    [string[]]$Repos,
    [SecureString]$Token,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# NOTE: the first entry in your list looked like two names run together
# ("...virtual-drawin" + "cxs-winner-picked-content"). It is kept as given and will
# be reported as NOT FOUND - correct the name(s) here if needed.
$DefaultRepos = @(
    'cxs-olk-content-virtual-drawincxs-winner-picked-content'
    'cxs-olk-lib-aristocrat-google-gson'
    'cxs-olk-lib-JavaLinux'
    'cxs-olk-lib-mbox-libgdx'
    'cxs-olk-lib-packages.mediaeditor'
    'cxs-olk-lib-Random-Rewards'
    'cxs-olk-product-concentrator'
    'cxs-olk-product-ExtLevelRouter'
    'cxs-olk-product-license-manager'
    'cxs-olk-product-linux-image-builder'
    'cxs-olk-product-mbox'
    'cxs-olk-product-mediasign-html'
    'cxs-olk-product-megamic'
    'cxs-olk-product-nmenu'
    'cxs-olk-product-onelink'
    'cxs-olk-product-onelink-amadeus'
    'cxs-olk-product-onelink-everi-consumer'
    'cxs-olk-product-onelink-firmware'
    'cxs-olk-product-onelink-g2s'
    'cxs-olk-product-onelink-hyatt-envision'
    'cxs-olk-product-onelink-infor'
    'cxs-olk-product-onelink-mediarouter'
    'cxs-olk-product-onelink-multicast-proxy'
    'cxs-olk-product-onelink-nconnect'
    'cxs-olk-product-onelink-phi-kiosk'
    'cxs-olk-product-onelink-report-server'
    'cxs-olk-product-onelink-rpm'
    'cxs-olk-product-onelink-webevents'
    'cxs-olk-product-PAL-264_OS'
    'cxs-olk-product-pt206'
    'cxs-olk-product-totalizer'
    'cxs-olk-product-TotalizerInstaller'
    'cxs-olk-product-virtualdrawings'
)
if (-not $Repos -or $Repos.Count -eq 0) { $Repos = $DefaultRepos }

if (-not $OutputDir) {
    $OutputDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

# ---- token (asked for, kept in memory only) ------------------------------------
if (-not $Token) {
    Write-Host "Enter your GitHub Personal Access Token (input is hidden; press Enter to try without one - private repos will fail)." -ForegroundColor Cyan
    $Token = Read-Host -Prompt 'GitHub token' -AsSecureString
}
$plainToken = ''
if ($Token -and $Token.Length -gt 0) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    try { $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$headers = @{
    'Accept'               = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'Get-GitHubBranches.ps1'
}
if ($plainToken) { $headers['Authorization'] = "Bearer $plainToken" }

function Get-StatusCode($err) {
    try { return [int]$err.Exception.Response.StatusCode } catch { return 0 }
}

function Invoke-GitHub([string]$Uri) {
    $resp = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -ErrorAction Stop
    # Windows PowerShell 5.1 hands back a JSON array as ONE object; enumerate it so
    # callers always get individual items (otherwise counts/paging are wrong).
    foreach ($item in $resp) { $item }
}

function Get-FriendlyError($err) {
    switch (Get-StatusCode $err) {
        401 { 'Token rejected (401) - wrong/expired token.' }
        403 { 'Forbidden (403) - token not authorized for this org (SSO?) or rate limit hit.' }
        404 { 'NOT FOUND (404) - repo name is wrong, or the token has no access to it.' }
        default { $err.Exception.Message }
    }
}

# ---- sanity check the token ----------------------------------------------------
if ($plainToken) {
    try {
        $me = Invoke-GitHub 'https://api.github.com/user'
        Write-Host "Authenticated as: $($me.login)" -ForegroundColor Green
    } catch {
        Write-Host "Token check failed: $(Get-FriendlyError $_)" -ForegroundColor Red
        exit 1
    }
}

# ---- fetch ---------------------------------------------------------------------
$branchRows  = New-Object System.Collections.Generic.List[object]
$summaryRows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($repo in $Repos) {
    $i++
    Write-Progress -Activity "Fetching branches from $Org" -Status "$repo ($i of $($Repos.Count))" `
        -PercentComplete (($i / $Repos.Count) * 100)
    try {
        $info    = Invoke-GitHub "https://api.github.com/repos/$Org/$repo"
        $default = $info.default_branch
        $names   = New-Object System.Collections.Generic.List[object]
        $page = 1
        while ($true) {
            $batch = @(Invoke-GitHub "https://api.github.com/repos/$Org/$repo/branches?per_page=100&page=$page")
            foreach ($b in $batch) { $names.Add($b) }
            if ($batch.Count -lt 100) { break }
            $page++
        }
        foreach ($b in ($names | Sort-Object { $_.name })) {
            $branchRows.Add([pscustomobject]@{
                Repository = $repo
                Branch     = $b.name
                IsDefault  = if ($b.name -eq $default) { 'Yes' } else { '' }
                Protected  = if ($b.protected) { 'Yes' } else { '' }
                LastSha    = $b.commit.sha
            })
        }
        $summaryRows.Add([pscustomobject]@{
            Repository    = $repo
            BranchCount   = $names.Count
            DefaultBranch = $default
            Archived      = if ($info.archived) { 'Yes' } else { '' }
            Status        = 'OK'
        })
        Write-Host ("[{0,2}/{1}] {2}  ->  {3} branches" -f $i, $Repos.Count, $repo, $names.Count)
    } catch {
        $msg = Get-FriendlyError $_
        $summaryRows.Add([pscustomobject]@{
            Repository = $repo; BranchCount = 0; DefaultBranch = ''; Archived = ''; Status = $msg
        })
        Write-Host ("[{0,2}/{1}] {2}  ->  {3}" -f $i, $Repos.Count, $repo, $msg) -ForegroundColor Yellow
    }
}
Write-Progress -Activity "Fetching branches from $Org" -Completed
$plainToken = $null

# ---- outputs -------------------------------------------------------------------
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $OutputDir "${Org}_AllBranches_$stamp.csv"
$sumPath = Join-Path $OutputDir "${Org}_BranchSummary_$stamp.csv"
$branchRows  | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
$summaryRows | Export-Csv -Path $sumPath -NoTypeInformation -Encoding UTF8

# Optional Excel workbook (2 sheets) via Excel COM, if Excel is installed.
$xlsxPath = Join-Path $OutputDir "${Org}_AllBranches_$stamp.xlsx"
$xlsxOk = $false
$excel = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()

    # Only ever assign STRINGS to Value2: the Windows PowerShell COM binder locks
    # Value2 to the first type it sees and throws on later ints/arrays. Text columns
    # are pre-formatted '@' so names/SHAs stay text; numeric columns are left General
    # so Excel parses "12" back into a number.
    function Write-Sheet($ws, $rows, $cols, [int[]]$numericCols = @()) {
        for ($c = 1; $c -le $cols.Count; $c++) {
            if ($numericCols -notcontains $c) { $ws.Columns.Item($c).NumberFormat = '@' }
        }
        for ($c = 0; $c -lt $cols.Count; $c++) { $ws.Cells.Item(1, $c + 1).Value2 = [string]$cols[$c] }
        for ($r = 0; $r -lt $rows.Count; $r++) {
            for ($c = 0; $c -lt $cols.Count; $c++) {
                $ws.Cells.Item($r + 2, $c + 1).Value2 = [string]$rows[$r].($cols[$c])
            }
        }
        $hdr = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $cols.Count))
        $hdr.Font.Bold = $true
        $hdr.Interior.Color = 0xF7EAD9
        $ws.Columns.AutoFit() | Out-Null
        $ws.Application.ActiveWindow.SplitRow = 1
        $ws.Application.ActiveWindow.FreezePanes = $true
    }

    $ws1 = $wb.Worksheets.Item(1); $ws1.Name = 'Branch Summary'
    Write-Sheet $ws1 $summaryRows @('Repository', 'BranchCount', 'DefaultBranch', 'Archived', 'Status') @(2)
    $ws2 = $wb.Worksheets.Add([Type]::Missing, $ws1); $ws2.Name = 'All Branches'
    Write-Sheet $ws2 $branchRows @('Repository', 'Branch', 'IsDefault', 'Protected', 'LastSha')

    $wb.SaveAs($xlsxPath, 51)
    $wb.Close($false)
    $xlsxOk = $true
} catch {
    Write-Host "Excel workbook skipped (Excel not available or failed): $($_.Exception.Message)" -ForegroundColor DarkGray
} finally {
    if ($excel) { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
}

$ok = @($summaryRows | Where-Object { $_.Status -eq 'OK' }).Count
Write-Host ""
Write-Host "Done. $ok of $($Repos.Count) repos fetched, $($branchRows.Count) branches total." -ForegroundColor Green
Write-Host "  CSV (all branches): $csvPath"
Write-Host "  CSV (summary)     : $sumPath"
if ($xlsxOk) { Write-Host "  Excel             : $xlsxPath" }
$bad = @($summaryRows | Where-Object { $_.Status -ne 'OK' })
if ($bad.Count -gt 0) {
    Write-Host "`nRepos with problems:" -ForegroundColor Yellow
    $bad | ForEach-Object { Write-Host "  $($_.Repository): $($_.Status)" -ForegroundColor Yellow }
}
