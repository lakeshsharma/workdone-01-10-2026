# Offline regression tests: load definitions only; never launch Foreman or SSH.
[CmdletBinding()]
param([string]$BashPath = 'C:\Program Files\Git\bin\bash.exe')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'OneLinkAdminTool.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$names = @('ConvertTo-OneLinkBashArg','ConvertTo-OneLinkDatabaseIdentifier','ConvertTo-OneLinkSqlString','Get-OneLinkDatabaseShell','ConvertTo-OneLinkDatabaseCommand','Invoke-OneLinkDatabaseCommand','New-OneLinkMysqlSqlCommand','Invoke-OneLinkCreateDatabaseUser','Invoke-OneLinkCreateDatabase','Invoke-OneLinkGrantPrivileges','New-OneLinkDatabaseExportCommand','New-OneLinkDatabaseImportCommand','Get-OneLinkDatabaseWorkerFunctions','New-OneLinkDatabaseJobCommand','Invoke-OneLinkMysqlQuery')
foreach ($name in $names) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Missing function: $name" }
    Invoke-Expression $fn.Extent.Text
}
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -and $caught -match $Pattern) "Expected error matching $Pattern; got: $caught"
}
Assert ((ConvertTo-OneLinkDatabaseIdentifier 'lakesh-test') -ceq '`lakesh-test`') 'Hyphenated database name changed.'
Assert ((ConvertTo-OneLinkDatabaseIdentifier 'a`b') -ceq '`a``b`') 'Backtick escaping failed.'
Assert-Throws { ConvertTo-OneLinkDatabaseIdentifier "test1`r" } 'Database name'
Assert-Throws { New-OneLinkDatabaseImportCommand mysql /tmp/backup.sql } 'system database'
Assert-Throws { New-OneLinkDatabaseJobCommand 'true' '../bad' } 'pattern'
$workerDefinitions = Get-OneLinkDatabaseWorkerFunctions
$rs = [powershell]::Create()
try {
    [void]$rs.AddScript($workerDefinitions + "`nNew-OneLinkDatabaseExportCommand -DatabaseName 'test-db' -FilePath '/tmp/test.sql.gz'")
    $workerCommand = $rs.Invoke()
    Assert (-not $rs.HadErrors -and $workerCommand.Count -eq 1) 'Background command builders failed in an isolated runspace.'
} finally { $rs.Dispose() }
if (-not (Test-Path -LiteralPath $BashPath)) { throw 'Git Bash is required for offline shell regression tests.' }
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('olk_db_tests_' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testDir)
$utf8 = New-Object Text.UTF8Encoding($false)
function Write-TestFile([string]$Name, [string]$Text) { [IO.File]::WriteAllText((Join-Path $testDir $Name), $Text.Replace("`r`n", "`n"), $utf8) }
Write-TestFile 'mysql' @'
#!/usr/bin/env bash
if [ "${MOCK_MYSQL_FAIL:-0}" = 1 ]; then echo 'simulated mysql failure' >&2; exit 9; fi
case "$*" in *--execute=*) exit 0;; esac
input=$(cat)
printf '%s\n' "$input" >> "$MOCK_SQL"
# Minimal state so the new existence-check SELECTs behave like a real server:
# once a CREATE USER has been seen, later "does this user exist" queries say yes.
if printf '%s' "$input" | grep -q 'CREATE USER'; then : > "$MOCK_USER_MARKER"; fi
if printf '%s' "$input" | grep -q 'SELECT 1 FROM mysql.user' && [ -f "$MOCK_USER_MARKER" ]; then echo 1; fi
'@
Write-TestFile 'mysqldump' @'
#!/usr/bin/env bash
if [ "${MOCK_DUMP_FAIL:-0}" = 1 ]; then echo 'simulated dump failure' >&2; exit 8; fi
if [ "${MOCK_REPLICATION_FAIL:-0}" = 1 ] && [[ "$*" == *--master-data* ]]; then exit 7; fi
printf 'CREATE TABLE example (id INT);\nINSERT INTO example VALUES (1);\n'
'@
Write-TestFile 'sudo' @'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
exec "$@"
'@
$unixDir = (& $BashPath -c '/usr/bin/cygpath -u "$1"' -- $testDir).Trim()
$sqlFile = Join-Path $testDir 'received.sql'
$script:mockMysqlFail = '0'; $script:mockDumpFail = '0'; $script:mockReplicationFail = '0'
function Run-TestBash([string]$Command) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $BashPath; $psi.Arguments = '--noprofile --norc'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['PATH'] = $testDir + ';' + $env:PATH
    $psi.EnvironmentVariables['MOCK_SQL'] = "$unixDir/received.sql"
    $psi.EnvironmentVariables['MOCK_USER_MARKER'] = "$unixDir/user_exists"
    $psi.EnvironmentVariables['MOCK_MYSQL_FAIL'] = $script:mockMysqlFail
    $psi.EnvironmentVariables['MOCK_DUMP_FAIL'] = $script:mockDumpFail
    $psi.EnvironmentVariables['MOCK_REPLICATION_FAIL'] = $script:mockReplicationFail
    $process = [Diagnostics.Process]::Start($psi)
    $process.StandardInput.Write("export PATH=" + (ConvertTo-OneLinkBashArg $unixDir) + ":/usr/bin:/bin:`$PATH`n" + $Command + "`n")
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $result = [pscustomobject]@{ ExitStatus = $process.ExitCode; Output = $stdout; Error = $stderr }
    $process.Dispose()
    return $result
}
function Invoke-OneLinkSshCommand { param($Session, $Command, $TimeoutSeconds) return Run-TestBash $Command }
try {
    $permissions = Run-TestBash ('chmod +x ' + (ConvertTo-OneLinkBashArg "$unixDir/mysql") + ' ' + (ConvertTo-OneLinkBashArg "$unixDir/mysqldump") + ' ' + (ConvertTo-OneLinkBashArg "$unixDir/sudo"))
    Assert ($permissions.ExitStatus -eq 0) $permissions.Error
    $settings = @{ Ssh = @{ CommandTimeoutSeconds = 30 } }
    Invoke-OneLinkCreateDatabase -Session test -Settings $settings -DatabaseName 'lakesh-test' | Out-Null
    Invoke-OneLinkCreateDatabaseUser -Session test -Settings $settings -Username "o'brien" -Password 'p''a\ss$word`!' -AllowedIp localhost | Out-Null
    Invoke-OneLinkGrantPrivileges -Session test -Settings $settings -Username "o'brien" -Password '' -DatabaseName 'test1' -AllowedIp localhost | Out-Null
    $sql = [IO.File]::ReadAllText($sqlFile)
    Assert ($sql.Contains('CREATE DATABASE IF NOT EXISTS `lakesh-test`;')) 'Database SQL was corrupted in transit.'
    Assert ($sql.Contains("'o''brien'@'localhost'")) 'Account or allowed-host quoting failed.'
    Assert ($sql.Contains("'p''a\ss`$word``!'")) 'Password was changed by shell expansion.'
    Assert (-not $sql.Contains("`r") -and $sql -notmatch '(?m)^SQL$') 'CRLF/heredoc corruption returned.'
    Assert (([regex]::Matches($sql, 'ALTER USER')).Count -eq 0) 'Create DB User (new account) or Grant without password unexpectedly changed credentials.'
    $script:mockMysqlFail = '1'
    Assert-Throws { Invoke-OneLinkCreateDatabase -Session test -Settings $settings -DatabaseName test } 'Database command failed \(exit 9\)'
    Assert-Throws { Invoke-OneLinkMysqlQuery -Session test -Sql 'SHOW DATABASES' } 'Database command failed'
    $script:mockMysqlFail = '0'
    foreach ($suffix in @('.sql', '.sql.gz')) {
        $destination = "$unixDir/backup with space$suffix"
        $script:mockReplicationFail = '1'
        $export = Run-TestBash (New-OneLinkDatabaseExportCommand 'lakesh-test' $destination)
        Assert ($export.ExitStatus -eq 0) "Export failed: $($export.Error)"
        $script:mockReplicationFail = '0'
        $import = Run-TestBash (New-OneLinkDatabaseImportCommand 'lakesh-test' $destination)
        Assert ($import.ExitStatus -eq 0) "Import failed: $($import.Error)"
        $script:mockDumpFail = '1'
        $before = [IO.File]::ReadAllBytes((Join-Path $testDir "backup with space$suffix"))
        $failedExport = Run-TestBash (New-OneLinkDatabaseExportCommand 'lakesh-test' $destination)
        Assert ($failedExport.ExitStatus -ne 0) 'Failed export was reported as successful.'
        $after = [IO.File]::ReadAllBytes((Join-Path $testDir "backup with space$suffix"))
        Assert ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String($after)) 'Failed export overwrote the existing backup.'
        $script:mockDumpFail = '0'
    }
    Write-TestFile 'bad.sql.gz' 'not gzip'
    $before = [IO.File]::ReadAllText($sqlFile)
    $badImport = Run-TestBash (New-OneLinkDatabaseImportCommand 'lakesh-test' "$unixDir/bad.sql.gz")
    Assert ($badImport.ExitStatus -ne 0 -and [IO.File]::ReadAllText($sqlFile) -ceq $before) 'Corrupt backup reached DROP DATABASE.'
    # Exercise the actual background workers with SSH and module loading mocked.
    # Their external exit status must determine Ok, including Server destinations.
    function Import-Module {}
    function New-SSHSession { return [pscustomobject]@{ Session = [pscustomobject]@{} } }
    function Remove-SSHSession {}
    function Invoke-SSHCommand { return [pscustomobject]@{ ExitStatus = $script:workerExit; Output = @('worker-result'); Error = @() } }
    $DatabaseFunctions = Get-OneLinkDatabaseWorkerFunctions
    $ModulesRoot = 'offline-test'; $SrvPass = 'offline-test'; $SrvUser = 'offline-test'; $SrvHost = 'offline-test'; $SrvPort = 22
    $Db = 'test-db'; $File = '/tmp/offline.sql'; $Loc = 'Server'; $Timeout = 30; $JobId = '0123456789abcdef0123456789abcdef'
    foreach ($workerName in @('ExportWorker','ImportWorker')) {
        $assignment = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $workerName) }, $true)
        Invoke-Expression $assignment.Extent.Text
        $worker = Get-Variable -Name $workerName -Scope Script -ValueOnly
        foreach ($script:workerExit in @(0, 9)) {
            $sync = @{ Cancel = $false; Status = ''; Done = $false; Ok = $false; Message = ''; Client = $null }
            & $worker
            Assert ($sync.Done -and $sync.Ok -eq ($script:workerExit -eq 0)) "$workerName falsely reported success or failed to finish."
        }
    }
    $job = New-OneLinkDatabaseJobCommand -Command (New-OneLinkDatabaseExportCommand 'test-db' '/tmp/offline.sql') -JobId $JobId
    $syntaxPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($job))
    $syntax = Run-TestBash ("printf '%s' '$syntaxPayload' | base64 --decode | bash -n")
    Assert ($syntax.ExitStatus -eq 0) 'Scoped job shell syntax failed.'
    Add-Type -AssemblyName PresentationFramework
    $xamlAssignment = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:MainWindowXaml' }, $true)
    Invoke-Expression $xamlAssignment.Extent.Text
    $window = [Windows.Markup.XamlReader]::Parse($script:MainWindowXaml)
    Assert ($null -ne $window.FindName('CmbGrantHost')) 'Grant account-host control is missing.'
    $window.Close()
    'PASS: syntax, isolated worker builders, Bash/SQL transport, account quoting, error propagation, plain/gzip backup round trips, replication fallback, existing-backup preservation and corrupt-restore rejection. No live databases were used.'
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    $root = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^olk_db_tests_[a-f0-9]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
