#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$OutputFile,
    [switch]$AssembleOnly
)

# ============================================================================
#  Build script for the OneLink Administration Tool.
#
#  The source code lives as ordered part files under src\ (see src\README.md).
#  PS2EXE compiles ONE script file, so step 0 below joins the parts - unchanged,
#  byte for byte, in the order listed in src\build-order.txt - into the single
#  OneLinkAdminTool.ps1, which is then compiled exactly as before.
#
#  It guards against the things that have produced broken EXEs:
#    1. Compiling STALE source where the embedded Posh-SSH blob is missing
#       (e.g. an old editor buffer was saved over the file).
#    2. ps2exe not importing because it lives under OneDrive-redirected
#       Documents and is not on the module path in a non-interactive shell.
#    3. A new part file that was never added to src\build-order.txt (it would
#       silently be left out of the EXE) - the build stops and names it.
#
#  Usage:
#     .\Build.ps1                      assemble src\ -> OneLinkAdminTool.ps1, then compile the EXE
#     .\Build.ps1 -AssembleOnly        only (re)generate OneLinkAdminTool.ps1 (e.g. to run/test the .ps1 directly)
#     .\Build.ps1 -OutputFile .\test.exe
#     .\Build.ps1 -InputFile .\Some.ps1   compile that file as-is (no assembling)
# ============================================================================

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$assembleFromParts = [string]::IsNullOrWhiteSpace($InputFile)
if ([string]::IsNullOrWhiteSpace($InputFile))  { $InputFile  = Join-Path $root 'OneLinkAdminTool.ps1' }
if ([string]::IsNullOrWhiteSpace($OutputFile)) { $OutputFile = Join-Path $root 'OneLinkAdministrationTool.exe' }

Write-Host "== OneLink Administration Tool build ==" -ForegroundColor Cyan

# --- 0. Assemble the single-file script from the structured source parts ----
#  Pure concatenation - nothing is rewritten. Every part carries a UTF-8 BOM
#  (so editors / Windows PowerShell 5.1 read it correctly); the BOMs are dropped
#  here and exactly ONE BOM is written at the start of the assembled file.
if ($assembleFromParts) {
    $srcRoot  = Join-Path $root 'src'
    $manifest = Join-Path $srcRoot 'build-order.txt'
    if (-not (Test-Path -LiteralPath $manifest)) { throw "Build order file not found: $manifest" }

    $parts = @(Get-Content -LiteralPath $manifest | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($parts.Count -eq 0) { throw "src\build-order.txt lists no source parts." }

    # Guard: a part that exists under src\ but is not listed would be silently missing from the EXE.
    $listed  = @($parts | ForEach-Object { (Join-Path $srcRoot ($_ -replace '/', '\')).ToLowerInvariant() })
    $orphans = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -Filter '*.ps1' -File | Where-Object { $listed -notcontains $_.FullName.ToLowerInvariant() })
    if ($orphans.Count -gt 0) {
        throw ("These source files are not listed in src\build-order.txt (they would be missing from the EXE): " +
               (($orphans | ForEach-Object { $_.FullName.Substring($srcRoot.Length + 1) }) -join ', '))
    }

    $ms = New-Object System.IO.MemoryStream
    $ms.Write([byte[]](0xEF, 0xBB, 0xBF), 0, 3)
    foreach ($rel in $parts) {
        $path = Join-Path $srcRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path)) { throw "Source part listed in build-order.txt was not found: $rel" }
        $bytes = [IO.File]::ReadAllBytes($path)
        $skip = 0
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $skip = 3 }
        $ms.Write($bytes, $skip, $bytes.Length - $skip)
    }
    [IO.File]::WriteAllBytes($InputFile, $ms.ToArray())
    $hash = (Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash
    Write-Host ("Assembled {0} source parts -> {1} ({2:N0} bytes, SHA-256 {3}...)" -f $parts.Count, $InputFile, $ms.Length, $hash.Substring(0, 16)) -ForegroundColor Green
    if ($AssembleOnly) { return }
}
elseif ($AssembleOnly) {
    throw "-AssembleOnly cannot be combined with -InputFile."
}

# --- 1. Verify the source is complete (embedded Posh-SSH blob present) ------
if (-not (Test-Path -LiteralPath $InputFile)) { throw "Input file not found: $InputFile" }
$text = [IO.File]::ReadAllText($InputFile)

if ($text.Contains('__POSH_SSH_BASE64__')) {
    throw "STALE SOURCE: the embedded Posh-SSH blob is missing (placeholder '__POSH_SSH_BASE64__' still present). Do not compile this file."
}
if ($text.Length -lt 1MB) {
    throw ("STALE SOURCE: '{0}' is only {1:N2} MB - the embedded module blob appears to be missing (expected ~1.8 MB)." -f $InputFile, ($text.Length / 1MB))
}
Write-Host ("Source OK: {0:N2} MB, embedded Posh-SSH blob present." -f ($text.Length / 1MB)) -ForegroundColor Green

# --- 2. Make sure ps2exe is importable (handle OneDrive-redirected install) -
if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
    $manifest = $null

    $available = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
    if ($available) {
        $manifest = $available.Path
    }
    else {
        $installed = Get-InstalledModule -Name ps2exe -ErrorAction SilentlyContinue
        if ($installed) {
            $manifest = Join-Path $installed.InstalledLocation 'ps2exe.psd1'
        }
    }

    if (-not $manifest -or -not (Test-Path -LiteralPath $manifest)) {
        throw "ps2exe not found. Install it once with:  Install-Module ps2exe -Scope CurrentUser -Force"
    }

    Import-Module -Name $manifest -Force
    Write-Host ("Imported ps2exe from: {0}" -f $manifest) -ForegroundColor Green
}

# --- 3. Compile -------------------------------------------------------------
Write-Host "Compiling..." -ForegroundColor Cyan
$ps2exeArgs = @{ InputFile = $InputFile; OutputFile = $OutputFile; NoConsole = $true; STA = $true }
$iconFile = Join-Path $root 'Foreman.ico'
if (Test-Path -LiteralPath $iconFile) {
    $ps2exeArgs['IconFile'] = $iconFile
    Write-Host ("Using application icon: {0}" -f $iconFile) -ForegroundColor Green
}
else {
    Write-Warning "Foreman.ico not found next to Build.ps1 - building without a custom EXE icon."
}
Invoke-PS2EXE @ps2exeArgs

# --- 4. Verify the output embedded the module (size sanity check) -----------
if (-not (Test-Path -LiteralPath $OutputFile)) { throw "Build produced no output file." }
$exe = Get-Item -LiteralPath $OutputFile
Write-Host ("Built: {0} ({1:N2} MB)" -f $exe.FullName, ($exe.Length / 1MB)) -ForegroundColor Green

if ($exe.Length -lt 1MB) {
    Write-Warning "The EXE is under 1 MB - the embedded Posh-SSH module may be MISSING. Do not distribute this build."
}
else {
    Write-Host "EXE size looks correct - embedded module is present. Ready to distribute." -ForegroundColor Green
}
