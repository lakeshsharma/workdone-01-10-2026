# ----------------------------------------------------------------------------
#  Config import / export (CSV) - default field values, NO passwords, NO IPs
# ----------------------------------------------------------------------------

# The fields saved/restored by the CSV config. Server rows (IPs, credentials,
# roles) and all passwords are intentionally excluded.
function Get-OneLinkConfigFields {
    return @(
        @{ Key = 'DbUser';          Ctrl = $TxtDbUser;          Type = 'text';  Section = 'Database' },
        @{ Key = 'DbAllowedIp';     Ctrl = $CmbDbUserIp;        Type = 'text';  Section = 'Database' },
        @{ Key = 'DatabaseName';    Ctrl = $TxtDatabaseName;    Type = 'text';  Section = 'Database' },
        @{ Key = 'GrantHost';       Ctrl = $CmbGrantHost;       Type = 'text'; Section = 'Database' },
        @{ Key = 'GrantUser';       Ctrl = $CmbGrantUser;       Type = 'text';  Section = 'Database' },
        @{ Key = 'ExportDatabase';  Ctrl = $CmbExportDb;        Type = 'text';  Section = 'Database' },
        @{ Key = 'ExportFile';      Ctrl = $TxtExportFile;      Type = 'text';  Section = 'Database' },
        @{ Key = 'ImportDatabase';  Ctrl = $CmbImportDb;        Type = 'text';  Section = 'Database' },
        @{ Key = 'ImportFile';      Ctrl = $TxtImportFile;      Type = 'text';  Section = 'Database' },
        @{ Key = 'PackageFolder';   Ctrl = $TxtPackagePath;     Type = 'text';  Section = 'Package' },
        @{ Key = 'RemoteDirectory'; Ctrl = $TxtRemoteDirectory; Type = 'text';  Section = 'Package' },
        @{ Key = 'InstallReason';   Ctrl = $TxtInstallReason;   Type = 'text';  Section = 'Package' },
        @{ Key = 'InstallMode';     Ctrl = $CmbInstallMode;     Type = 'combo'; Section = 'Package' },
        @{ Key = 'SslAfterInstall'; Ctrl = $CmbSslAfterInstall; Type = 'combo'; Section = 'Package' },
        @{ Key = 'ServiceAction';   Ctrl = $CmbServiceAction;   Type = 'combo'; Section = 'Service' },
        @{ Key = 'CertFile';        Ctrl = $TxtCertFile;        Type = 'text';  Section = 'Certificate' },
        @{ Key = 'CertDestination'; Ctrl = $TxtCertDest;        Type = 'text';  Section = 'Certificate' },
        @{ Key = 'CertType';        Ctrl = $CmbCertType;        Type = 'combo'; Section = 'Certificate' },
        @{ Key = 'CertScanPath';    Ctrl = $TxtCertScanPath;    Type = 'text';  Section = 'Certificate' }
    )
}

function Set-OneLinkComboByText {
    param($ComboBox, [string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return }
    for ($i = 0; $i -lt $ComboBox.Items.Count; $i++) {
        $item = $ComboBox.Items[$i]
        $itemText = if ($item.PSObject.Properties.Name -contains 'Content') { [string]$item.Content } else { [string]$item }
        if ($itemText -eq $Text) { $ComboBox.SelectedIndex = $i; return }
    }
}

# One consistent, professional column layout for the whole config CSV. Each row
# is tagged by RecordType: 'Server' rows carry the server inventory (Password is
# left BLANK on export - fill it in before importing); 'Setting' rows carry the
# form field values. This keeps everything in a single, importable file.
function New-OneLinkConfigRow {
    param(
        [string]$RecordType, [string]$HostName = '', [string]$Port = '', [string]$Username = '',
        [string]$Password = '', [string]$Roles = '', [string]$OS = '', [string]$SettingName = '', [string]$SettingValue = ''
    )
    return [PSCustomObject][ordered]@{
        RecordType = $RecordType; Host = $HostName; Port = $Port; Username = $Username
        Password = $Password; Roles = $Roles; OS = $OS; SettingName = $SettingName; SettingValue = $SettingValue
    }
}

# Minimal XML/HTML escaper (System.Web may not be loaded in the packaged EXE).
function ConvertTo-OneLinkHtmlText {
    param([string]$Text)
    $t = [string]$Text
    $t = $t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
    return $t
}

# ----------------------------------------------------------------------------
#  Standalone .xlsx engine (no external module / no Excel needed). Writes a real,
#  colourful, multi-worksheet Excel file and reads it back, using only the
#  System.IO.Compression support the EXE already loads. Style indices in the
#  embedded styles.xml: 1 header-navy, 2 header-blue, 3 header-violet,
#  4 header-cyan, 5 header-green, 6 key-cell (bold, light fill), 7 value.
# ----------------------------------------------------------------------------
function Get-OneLinkXlsxCol { param([int]$n) $s = ''; while ($n -gt 0) { $m = ($n - 1) % 26; $s = [char](65 + $m) + $s; $n = [int](($n - $m - 1) / 26) }; return $s }

function Get-OneLinkXlsxStyles {
    return @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3">
<font><sz val="11"/><color rgb="FF0F172A"/><name val="Segoe UI"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Segoe UI"/></font>
<font><b/><sz val="11"/><color rgb="FF334155"/><name val="Segoe UI"/></font>
</fonts>
<fills count="8">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF1E3A8A"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF2563EB"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF7C3AED"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF0891B2"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF16A34A"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFEEF2FF"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="8">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="1" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="1" fillId="4" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="1" fillId="5" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="1" fillId="6" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="2" fillId="7" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
'@
}

# Sheet XML from $Rows (array of rows; each row = array of @{ v=text; s=styleIndex }).
function Get-OneLinkXlsxSheetXml {
    param([object[]]$Rows, [int[]]$ColWidths)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    if ($ColWidths -and $ColWidths.Count -gt 0) {
        [void]$sb.Append('<cols>')
        for ($i = 0; $i -lt $ColWidths.Count; $i++) { $c = $i + 1; [void]$sb.Append("<col min=`"$c`" max=`"$c`" width=`"$($ColWidths[$i])`" customWidth=`"1`"/>") }
        [void]$sb.Append('</cols>')
    }
    [void]$sb.Append('<sheetData>')
    $r = 0
    foreach ($row in $Rows) {
        $r++
        [void]$sb.Append("<row r=`"$r`">")
        $c = 0
        foreach ($cell in $row) {
            $c++
            $ref = (Get-OneLinkXlsxCol $c) + $r
            $s = [int]$cell.s
            $txt = ConvertTo-OneLinkHtmlText ([string]$cell.v)
            [void]$sb.Append("<c r=`"$ref`" s=`"$s`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$txt</t></is></c>")
        }
        [void]$sb.Append('</row>')
    }
    [void]$sb.Append('</sheetData></worksheet>')
    return $sb.ToString()
}

# Write a multi-sheet .xlsx. $Sheets = ordered array of @{ Name; Rows; ColWidths }.
function New-OneLinkXlsx {
    param([string]$Path, [object[]]$Sheets)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        $addEntry = {
            param($archive, $name, $content)
            $e = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
            $w = New-Object System.IO.StreamWriter($e.Open(), (New-Object System.Text.UTF8Encoding($false)))
            $w.Write($content); $w.Flush(); $w.Dispose()
        }
        $n = $Sheets.Count
        $ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        for ($i = 1; $i -le $n; $i++) { $ct += "<Override PartName=`"/xl/worksheets/sheet$i.xml`" ContentType=`"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml`"/>" }
        $ct += '</Types>'
        & $addEntry $zip '[Content_Types].xml' $ct
        & $addEntry $zip '_rels/.rels' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        $wb = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        for ($i = 1; $i -le $n; $i++) { $nm = ConvertTo-OneLinkHtmlText ([string]$Sheets[$i - 1].Name); $wb += "<sheet name=`"$nm`" sheetId=`"$i`" r:id=`"rId$i`"/>" }
        $wb += '</sheets></workbook>'
        & $addEntry $zip 'xl/workbook.xml' $wb
        $wr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        for ($i = 1; $i -le $n; $i++) { $wr += "<Relationship Id=`"rId$i`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet$i.xml`"/>" }
        $sid = $n + 1
        $wr += "<Relationship Id=`"rId$sid`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles`" Target=`"styles.xml`"/></Relationships>"
        & $addEntry $zip 'xl/_rels/workbook.xml.rels' $wr
        & $addEntry $zip 'xl/styles.xml' (Get-OneLinkXlsxStyles)
        for ($i = 1; $i -le $n; $i++) { & $addEntry $zip "xl/worksheets/sheet$i.xml" (Get-OneLinkXlsxSheetXml -Rows $Sheets[$i - 1].Rows -ColWidths $Sheets[$i - 1].ColWidths) }
        $zip.Dispose()
    }
    finally { $fs.Dispose() }
}

# Read an .xlsx back to an ordered map: sheetName -> array of string-cell rows.
# Handles inline strings (our writer) AND shared strings + numbers (files re-saved
# by Excel after the user edits them).
function Import-OneLinkXlsx {
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read)
        $readEntry = {
            param($archive, $name)
            $e = $archive.GetEntry($name); if ($null -eq $e) { return $null }
            $rr = New-Object System.IO.StreamReader($e.Open()); $t = $rr.ReadToEnd(); $rr.Dispose(); return $t
        }
        $strip = {
            param($x)
            $x = $x -replace 'xmlns(:\w+)?="[^"]*"', ''
            $x = $x -replace '<(/?)[A-Za-z_][\w.-]*:', '<$1'
            $x = $x -replace '\s[A-Za-z_][\w.-]*:([A-Za-z_][\w.-]*=)', ' $1'
            return $x
        }
        $shared = @()
        $ssRaw = & $readEntry $zip 'xl/sharedStrings.xml'
        if ($ssRaw) { [xml]$ssx = (& $strip $ssRaw); foreach ($si in $ssx.sst.si) { $shared += , ([string]$si.InnerText) } }
        [xml]$wbx = (& $strip (& $readEntry $zip 'xl/workbook.xml'))
        [xml]$relx = (& $strip (& $readEntry $zip 'xl/_rels/workbook.xml.rels'))
        $relMap = @{}; foreach ($rel in $relx.Relationships.Relationship) { $relMap[[string]$rel.Id] = [string]$rel.Target }
        $result = [ordered]@{}
        foreach ($sh in $wbx.workbook.sheets.sheet) {
            $name = [string]$sh.name
            $target = $relMap[[string]$sh.id]; if ([string]::IsNullOrEmpty($target)) { continue }
            if ($target -match '^/') { $target = $target.TrimStart('/') } else { $target = "xl/$target" }
            $sheetRaw = & $readEntry $zip $target; if ($null -eq $sheetRaw) { continue }
            [xml]$shx = (& $strip $sheetRaw)
            $rows = New-Object System.Collections.Generic.List[object]
            if ($shx.worksheet.sheetData) {
                foreach ($row in $shx.worksheet.sheetData.row) {
                    $cells = New-Object System.Collections.Generic.List[string]
                    foreach ($c in $row.c) {
                        $ct2 = [string]$c.t; $val = ''
                        if ($ct2 -eq 'inlineStr') { $val = [string]$c.is.InnerText }
                        elseif ($ct2 -eq 's') { $idx = 0; [void][int]::TryParse([string]$c.v, [ref]$idx); if ($idx -ge 0 -and $idx -lt $shared.Count) { $val = $shared[$idx] } }
                        else { $val = [string]$c.v }
                        $cells.Add($val)
                    }
                    $rows.Add($cells.ToArray())
                }
            }
            $result[$name] = $rows.ToArray()
        }
        $zip.Dispose()
        return $result
    }
    finally { $fs.Dispose() }
}

# Cell helper for building xlsx rows.
function New-OneLinkXlsxCell { param([string]$Value, [int]$Style = 7) return @{ v = $Value; s = $Style } }

# Build the workbook sheet layout for the config: a 'Servers' tab plus one tab per
# option group (Database / Package / Certificate / Service), each colour-headed.
# $ServerRows: @{Host;Port;Username;Password;Roles;OS}; $SettingRows: @{Key;Value;Section}.
function Get-OneLinkConfigSheets {
    param([object[]]$ServerRows, [object[]]$SettingRows)
    $sheets = @()
    $srows = @()
    $srows += , @( @('Host', 'Port', 'Username', 'Password', 'Roles', 'OS') | ForEach-Object { New-OneLinkXlsxCell $_ 1 } )
    foreach ($s in $ServerRows) {
        $srows += , @(
            (New-OneLinkXlsxCell ([string]$s.Host)),
            (New-OneLinkXlsxCell ([string]$s.Port)),
            (New-OneLinkXlsxCell ([string]$s.Username)),
            (New-OneLinkXlsxCell ([string]$s.Password)),
            (New-OneLinkXlsxCell ([string]$s.Roles)),
            (New-OneLinkXlsxCell ([string]$s.OS))
        )
    }
    $sheets += @{ Name = 'Servers'; Rows = $srows; ColWidths = @(20, 7, 18, 16, 30, 10) }

    $sectionStyle = @{ 'Database' = 2; 'Package' = 3; 'Certificate' = 4; 'Service' = 5 }
    foreach ($section in @('Database', 'Package', 'Certificate', 'Service')) {
        $items = @($SettingRows | Where-Object { $_.Section -eq $section })
        if ($items.Count -eq 0) { continue }
        $hstyle = [int]$sectionStyle[$section]
        $rows = @()
        $rows += , @( (New-OneLinkXlsxCell 'Option' $hstyle), (New-OneLinkXlsxCell 'Value' $hstyle) )
        foreach ($it in $items) {
            $rows += , @( (New-OneLinkXlsxCell ([string]$it.Key) 6), (New-OneLinkXlsxCell ([string]$it.Value)) )
        }
        $sheets += @{ Name = $section; Rows = $rows; ColWidths = @(26, 52) }
    }
    return $sheets
}

# Build a colourful, easy-to-read HTML view of the configuration (servers + all
# option groups). Opens in any browser; for reading / sharing / printing.
# $ServerRows: @{Host;Port;Username;Password;Roles;OS}; $SettingRows: @{Key;Value;Section}.
function ConvertTo-OneLinkConfigHtml {
    param([object[]]$ServerRows, [object[]]$SettingRows, [string]$Title, [switch]$IsTemplate)
    $enc = { param($s) ConvertTo-OneLinkHtmlText $s }
    $sectionColors = @{ 'Database' = '#2563EB'; 'Package' = '#7C3AED'; 'Certificate' = '#0891B2'; 'Service' = '#16A34A' }
    $stamp = (Get-Date).ToString('dd-MMM-yyyy HH:mm')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>$(& $enc $Title)</title>
<style>
 body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f7fb;color:#0f172a;margin:0;padding:24px;}
 .wrap{max-width:1000px;margin:0 auto;}
 .hd{background:linear-gradient(90deg,#2563eb,#4f46e5,#7c3aed);color:#fff;padding:18px 22px;border-radius:12px;}
 .hd h1{margin:0;font-size:22px;} .hd p{margin:4px 0 0;color:#dbe4ff;font-size:13px;}
 .card{background:#fff;border:1px solid #e2e8f0;border-radius:12px;margin:16px 0;overflow:hidden;box-shadow:0 1px 3px rgba(15,23,42,.06);}
 .cap{padding:10px 16px;font-weight:600;color:#fff;font-size:14px;}
 table{border-collapse:collapse;width:100%;font-size:13px;}
 th{background:#f1f5f9;text-align:left;padding:9px 14px;color:#334155;border-bottom:1px solid #e2e8f0;font-weight:600;}
 td{padding:8px 14px;border-bottom:1px solid #eef2f7;}
 tr:nth-child(even) td{background:#fafcff;}
 .k{color:#475569;width:34%;font-weight:600;}
 .muted{color:#94a3b8;font-style:italic;}
 .note{background:#eff6ff;border:1px solid #bfdbfe;color:#1e3a8a;border-radius:8px;padding:10px 14px;font-size:13px;margin:12px 0;}
 .foot{color:#94a3b8;font-size:12px;text-align:center;margin-top:18px;}
</style></head><body><div class="wrap">
<div class="hd"><h1>$($script:AppName) &#8212; Deployment Configuration</h1><p>$(& $enc $Title) &#183; generated $stamp</p></div>
"@)
    if ($IsTemplate) {
        [void]$sb.Append('<div class="note"><b>Template.</b> Fill in the values below (or edit the matching <b>.csv</b>), then use <b>Import Config</b> in ' + $script:AppName + '. Passwords are blank by design &#8212; add them in the CSV before importing.</div>')
    }
    # Servers card
    [void]$sb.Append('<div class="card"><div class="cap" style="background:#1e3a8a">Servers</div><table><tr><th>Host / IP</th><th>Port</th><th>Username</th><th>Password</th><th>Roles</th><th>OS</th></tr>')
    if (@($ServerRows).Count -eq 0) {
        [void]$sb.Append('<tr><td colspan="6" class="muted">(no server rows)</td></tr>')
    }
    else {
        foreach ($r in $ServerRows) {
            $pw = if ([string]::IsNullOrEmpty([string]$r.Password)) { '<span class="muted">(add in CSV)</span>' } else { '&#8226;&#8226;&#8226;&#8226;&#8226;&#8226;' }
            [void]$sb.Append("<tr><td>$(& $enc $r.Host)</td><td>$(& $enc $r.Port)</td><td>$(& $enc $r.Username)</td><td>$pw</td><td>$(& $enc $r.Roles)</td><td>$(& $enc $r.OS)</td></tr>")
        }
    }
    [void]$sb.Append('</table></div>')
    # Settings grouped by section
    foreach ($section in @('Database', 'Package', 'Certificate', 'Service')) {
        $items = @($SettingRows | Where-Object { $_.Section -eq $section })
        if ($items.Count -eq 0) { continue }
        $color = $sectionColors[$section]
        [void]$sb.Append("<div class=`"card`"><div class=`"cap`" style=`"background:$color`">$section</div><table><tr><th class=`"k`">Option</th><th>Value</th></tr>")
        foreach ($it in $items) {
            $val = if ([string]::IsNullOrWhiteSpace([string]$it.Value)) { '<span class="muted">(not set)</span>' } else { & $enc $it.Value }
            [void]$sb.Append("<tr><td class=`"k`">$(& $enc $it.Key)</td><td>$val</td></tr>")
        }
        [void]$sb.Append('</table></div>')
    }
    [void]$sb.Append("<div class=`"foot`">$($script:AppName) &#183; $($script:AppTagline)</div></div></body></html>")
    return $sb.ToString()
}

