<#
.SYNOPSIS
    Pulls the FULL detail of every open Cycode violation for a project (default:
    OneLink, project id 36416) - not just severity counts - and writes it to CSV
    and (if Excel is installed) an .xlsx workbook.

.DESCRIPTION
    Requires the `cycode` CLI to be installed and authenticated on THIS machine
    (separate from the Cycode-Stats app, which bundles its own copy):
        py -m pip install --upgrade cycode
        cycode auth

    This script does not know Cycode's exact per-violation schema in advance -
    it flattens whatever JSON fields Cycode returns for each violation into
    columns, so nothing is dropped just because we didn't anticipate a field
    name. Column names come straight from Cycode's response (e.g.
    "detection_details.repository_name", "policy_display_name", "risk_score",
    "created_date" ...) - inspect the first run's output to see what's there.

.EXAMPLE
    .\Get-CycodeFullDetail.ps1
    .\Get-CycodeFullDetail.ps1 -ProjectId 25214 -Status Open -OutputDir C:\Temp
#>
[CmdletBinding()]
param(
    [int]$ProjectId = 36416,      # OneLink
    [string]$Status = 'Open',
    [int]$PageSize = 1000,
    [int]$MaxDepth = 6,           # how deep to flatten nested objects/lists
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

if (-not $OutputDir) {
    $OutputDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

# ---- find the cycode executable -------------------------------------------------
function Find-CycodeExe {
    $found = Get-Command cycode -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $userSite = & py -c "import site; print(site.getusersitepackages())" 2>$null
            if ($userSite) {
                $candidate = Join-Path (Split-Path $userSite -Parent) 'Scripts\cycode.exe'
                if (Test-Path $candidate) { return $candidate }
            }
        } catch {}
    }
    if ($env:APPDATA) {
        $verInfo = & py -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')" 2>$null
        if ($verInfo) {
            $candidate = Join-Path $env:APPDATA "Python\Python$verInfo\Scripts\cycode.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }
    throw "Cycode CLI was not found. Install it with:`n  py -m pip install --upgrade cycode`nThen authenticate with:`n  cycode auth"
}

# ---- strip ANSI + pull the first balanced {...} that looks like our response ----
function Remove-Ansi([string]$Text) {
    # Build the ESC (0x1B) char explicitly - the `e escape sequence is NOT
    # recognized in Windows PowerShell 5.1 double-quoted strings (only in
    # PowerShell 7+), where it silently collapses to a literal 'e' instead,
    # turning this into a regex that corrupts real text containing "e_",
    # "e[A-Z]", etc. (e.g. "file_path" -> "filpath"). Verified via testing.
    $esc = [char]27
    $pattern = [regex]::Escape($esc) + '(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])'
    return [regex]::Replace($Text, $pattern, '')
}

function Get-CycodeJsonObject([string]$Text) {
    $clean = Remove-Ansi $Text
    $trimmed = $clean.Trim()
    if ($trimmed.StartsWith('{')) {
        try {
            $obj = $trimmed | ConvertFrom-Json -ErrorAction Stop
            if ($obj.PSObject.Properties.Name -contains 'items' -or $obj.PSObject.Properties.Name -contains 'next_page_token') {
                return $obj
            }
        } catch {}
    }
    # fall back: scan for a balanced {...} block anywhere in the text (handles
    # log/warning lines mixed into stdout), respecting quoted strings.
    $start = $clean.IndexOf('{')
    while ($start -ge 0) {
        $depth = 0; $inStr = $false; $esc = $false
        for ($i = $start; $i -lt $clean.Length; $i++) {
            $ch = $clean[$i]
            if ($esc) { $esc = $false; continue }
            if ($ch -eq '\') { if ($inStr) { $esc = $true }; continue }
            if ($ch -eq '"') { $inStr = -not $inStr; continue }
            if ($inStr) { continue }
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $candidate = $clean.Substring($start, $i - $start + 1)
                    try {
                        $obj = $candidate | ConvertFrom-Json -ErrorAction Stop
                        if ($obj.PSObject.Properties.Name -contains 'items' -or $obj.PSObject.Properties.Name -contains 'next_page_token') {
                            return $obj
                        }
                    } catch {}
                    break
                }
            }
        }
        $start = $clean.IndexOf('{', $start + 1)
    }
    throw "Could not find a valid Cycode JSON response in the CLI output."
}

function Invoke-CycodePage([string]$Exe, [string]$NextToken) {
    $cmdArgs = @('--output', 'json', 'platform', 'violations', 'list',
                 '--status', $Status, '--project-ids', $ProjectId,
                 '--page-size', $PageSize)
    if ($NextToken) { $cmdArgs += @('--next-page-token', $NextToken) }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $out = & $Exe @cmdArgs 2>&1 | Out-String
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            try { return Get-CycodeJsonObject $out }
            catch { if ($attempt -eq 3) { throw } }
        } else {
            $low = $out.ToLower()
            if ($low.Contains('credentials') -or $low.Contains('cycode auth')) {
                throw "Cycode authentication is required. Run 'cycode auth' and then run this script again."
            }
            if ($attempt -eq 3) { throw "Cycode request failed: $out" }
        }
        Start-Sleep -Seconds ($attempt * 2)
    }
}

# ---- flatten an arbitrary JSON object into dotted-path columns -----------------
function Get-FlattenedProperties {
    param($InputObject, [string]$Prefix = '', [int]$Depth = 0)

    $result = [ordered]@{}

    if ($null -eq $InputObject) {
        if ($Prefix) { $result[$Prefix] = '' }
        return $result
    }
    if ($Depth -ge $MaxDepth) {
        $result[$Prefix] = (ConvertTo-Json $InputObject -Compress -Depth 2)
        return $result
    }

    $isScalarLike = ($InputObject -is [string]) -or ($InputObject -is [ValueType])
    if (-not $isScalarLike -and ($InputObject -is [System.Collections.IEnumerable])) {
        $items = @($InputObject)
        if ($items.Count -eq 0) { $result[$Prefix] = ''; return $result }
        $hasComplex = $false
        foreach ($it in $items) {
            if ($it -is [PSCustomObject] -or (($it -is [System.Collections.IEnumerable]) -and -not ($it -is [string]))) {
                $hasComplex = $true; break
            }
        }
        if (-not $hasComplex) {
            $result[$Prefix] = ($items -join '; ')
        } else {
            for ($i = 0; $i -lt $items.Count; $i++) {
                $sub = Get-FlattenedProperties -InputObject $items[$i] -Prefix "$Prefix[$i]" -Depth ($Depth + 1)
                foreach ($k in $sub.Keys) { $result[$k] = $sub[$k] }
            }
        }
        return $result
    }

    if ($InputObject -is [PSCustomObject]) {
        foreach ($p in $InputObject.PSObject.Properties) {
            $key = if ($Prefix) { "$Prefix.$($p.Name)" } else { $p.Name }
            $sub = Get-FlattenedProperties -InputObject $p.Value -Prefix $key -Depth ($Depth + 1)
            foreach ($k in $sub.Keys) { $result[$k] = $sub[$k] }
        }
        return $result
    }

    $result[$Prefix] = $InputObject
    return $result
}

# ---- fetch every page, flatten every violation ----------------------------------
$exe = Find-CycodeExe
Write-Host "Cycode CLI: $exe" -ForegroundColor Cyan
Write-Host "Project ID: $ProjectId | Status: $Status" -ForegroundColor Cyan

$allRows = New-Object System.Collections.Generic.List[object]
$columnOrder = New-Object System.Collections.Generic.List[string]
$columnSeen = @{}
$token = $null
$page = 0
$total = 0

while ($true) {
    $page++
    Write-Host "Fetching page $page..." -NoNewline
    $data = Invoke-CycodePage -Exe $exe -NextToken $token
    $items = @($data.items)
    Write-Host " received $($items.Count)"

    foreach ($item in $items) {
        $flat = Get-FlattenedProperties -InputObject $item
        foreach ($k in $flat.Keys) {
            if (-not $columnSeen.ContainsKey($k)) {
                $columnSeen[$k] = $true
                [void]$columnOrder.Add($k)
            }
        }
        $allRows.Add($flat)
    }
    $total += $items.Count

    $token = $data.next_page_token
    if (-not $token) { break }
}

Write-Host "`nTotal violations fetched: $total" -ForegroundColor Green
Write-Host "Distinct columns found: $($columnOrder.Count)" -ForegroundColor Green

if ($total -eq 0) {
    Write-Host "No violations returned - nothing to write." -ForegroundColor Yellow
    return
}

# ---- build uniform rows (fill missing columns with '') --------------------------
$psRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $allRows) {
    $o = [ordered]@{}
    foreach ($col in $columnOrder) {
        $o[$col] = if ($row.Contains($col)) { [string]$row[$col] } else { '' }
    }
    $psRows.Add([pscustomobject]$o)
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $OutputDir "Cycode_${ProjectId}_FullDetail_$stamp.csv"
$psRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "CSV written: $csvPath" -ForegroundColor Green

# ---- optional Excel workbook (only ever assign STRINGS to Value2 - see notes) ---
$xlsxPath = Join-Path $OutputDir "Cycode_${ProjectId}_FullDetail_$stamp.xlsx"
$excel = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()
    $ws = $wb.Worksheets.Item(1)
    $ws.Name = 'Violations'

    $cols = $columnOrder.ToArray()
    for ($c = 0; $c -lt $cols.Count; $c++) { $ws.Columns.Item($c + 1).NumberFormat = '@' }
    for ($c = 0; $c -lt $cols.Count; $c++) { $ws.Cells.Item(1, $c + 1).Value2 = [string]$cols[$c] }

    # Excel COM chokes assigning millions of cells one-by-one; write in chunks.
    $chunk = 2000
    for ($r0 = 0; $r0 -lt $psRows.Count; $r0 += $chunk) {
        $rEnd = [Math]::Min($r0 + $chunk, $psRows.Count) - 1
        $n = $rEnd - $r0 + 1
        $data = New-Object 'object[,]' $n, $cols.Count
        for ($r = 0; $r -lt $n; $r++) {
            $src = $psRows[$r0 + $r]
            for ($c = 0; $c -lt $cols.Count; $c++) { $data[$r, $c] = [string]$src.($cols[$c]) }
        }
        $topRow = $r0 + 2
        $ws.Range($ws.Cells.Item($topRow, 1), $ws.Cells.Item($topRow + $n - 1, $cols.Count)).Value2 = $data
    }

    $hdr = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $cols.Count))
    $hdr.Font.Bold = $true
    $hdr.Interior.Color = 0xF7EAD9
    $ws.Application.ActiveWindow.SplitRow = 1
    $ws.Application.ActiveWindow.FreezePanes = $true
    $ws.Columns.AutoFilter() | Out-Null

    $wb.SaveAs($xlsxPath, 51)
    $wb.Close($false)
    Write-Host "Excel written: $xlsxPath" -ForegroundColor Green
} catch {
    Write-Host "Excel workbook skipped (Excel not available or failed): $($_.Exception.Message)" -ForegroundColor DarkGray
} finally {
    if ($excel) { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
}

Write-Host "`nDone. $total violations, $($columnOrder.Count) columns."
Write-Host "Open the CSV or Excel and check the column list against what your boss actually needs -"
Write-Host "this pulls every field Cycode returned; trim columns afterward if it's too wide."
