# ============================================================================
#  Shared shell quoting and direct database operations.
#  Legacy service/SSL helpers below remain separate from the Database tab.
# ============================================================================

# Quote a value as a single bash argument (safe for arbitrary text/passwords).
function ConvertTo-OneLinkBashArg {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

# Run an nmenu helper script over SSH with a sane PATH; throw on non-zero exit.
function Invoke-OneLinkNmenuCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutSeconds = 120
    )

    $prefixedPath = 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
    $full = "$prefixedPath; $Command"
    $result = Invoke-OneLinkSshCommand -Session $Session -Command $full -TimeoutSeconds $TimeoutSeconds

    $text = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
    if ($result.ExitStatus -ne 0) {
        throw ("nmenu command failed (exit {0}). {1}" -f $result.ExitStatus, $text)
    }
    return $text
}

# Database operations use the installed MySQL/MariaDB clients, never nmenu.
function ConvertTo-OneLinkDatabaseIdentifier {
    param([Parameter(Mandatory)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 64 -or $Name -match '[\x00-\x1f\x7f/\\.]' -or $Name.EndsWith(' ')) {
        throw 'Database name must be 1-64 characters and cannot contain control characters, dots, slashes or a trailing space.'
    }
    return '`' + $Name.Replace('`', '``') + '`'
}

function ConvertTo-OneLinkSqlString {
    param([AllowEmptyString()][string]$Value)
    if ($Value -match '[\x00\r\n]') { throw 'Database account values cannot contain NUL or line breaks.' }
    # Statements execute with NO_BACKSLASH_ESCAPES in their own session.
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-OneLinkDatabaseShell {
    return @'
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
db_run() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
mysql_client=$(command -v mysql || command -v mariadb) || { echo 'MySQL/MariaDB client is not installed.' >&2; exit 1; }
db_mysql() { db_run "$mysql_client" --protocol=SOCKET --user=root --default-character-set=utf8mb4 --binary-mode "$@"; }
'@
}

function ConvertTo-OneLinkDatabaseCommand {
    param([Parameter(Mandatory)][string]$Script)
    # Windows here-strings contain CRLF. Bash must receive LF, including heredoc
    # terminators and assignments. Transport the script as data, not shell syntax.
    $lf = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
    return "printf '%s' '$encoded' | base64 --decode | bash"
}

function Invoke-OneLinkDatabaseCommand {
    param($Session, [string]$Command, [int]$TimeoutSeconds = 120, [string[]]$Secrets = @())
    $result = Invoke-OneLinkSshCommand -Session $Session -Command (ConvertTo-OneLinkDatabaseCommand $Command) -TimeoutSeconds $TimeoutSeconds
    $text = (@($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
    foreach ($secret in $Secrets) {
        if ($secret) { $text = $text.Replace($secret, '********').Replace($secret.Replace("'", "''"), '********') }
    }
    if ($result.ExitStatus -ne 0) {
        $hint = if ($text -match '(?i)access denied|using password|sudo:') { ' Check that the SSH account can run sudo without a prompt and that root socket login is configured for the installed database client.' } else { '' }
        throw "Database command failed (exit $($result.ExitStatus)). $text$hint"
    }
    return $text
}

function New-OneLinkMysqlSqlCommand {
    param([string]$Sql)
    $sqlText = "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';`n" + $Sql
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sqlText))
    return (Get-OneLinkDatabaseShell) + "`n" + "printf '%s' '$payload' | base64 --decode | db_mysql --batch --skip-column-names"
}

# Run an existing .sql file (already on the target server) through the MySQL
# root socket - the direct equivalent of nmenu's 'ndb_run <file>'.
function New-OneLinkSqlScriptRunCommand {
    param([string]$FilePath)
    $fileArg = ConvertTo-OneLinkBashArg $FilePath
    return (Get-OneLinkDatabaseShell) + "`n" +
        "F=$fileArg`n" +
        'if [ ! -f "$F" ]; then echo "SQL script not found on the server: $F" >&2; exit 1; fi' + "`n" +
        'db_mysql < "$F"'
}

function Invoke-OneLinkCreateDatabaseUser {
    param($Session, $Settings, [string]$Username, [string]$Password, [AllowEmptyString()][string]$AllowedIp)
    if ([string]::IsNullOrWhiteSpace($Username)) { throw 'Database username is required.' }
    if ([string]::IsNullOrEmpty($Password)) { throw 'Database password is required.' }
    $ip = if ([string]::IsNullOrWhiteSpace($AllowedIp)) { '%' } else { $AllowedIp.Trim() }
    $userStr = ConvertTo-OneLinkSqlString $Username.Trim()
    $ipStr = ConvertTo-OneLinkSqlString $ip
    $account = "$userStr@$ipStr"

    # Check BEFORE creating so an existing account is reported as such, instead
    # of silently resetting its password (the previous unconditional ALTER USER).
    $existing = @(Invoke-OneLinkMysqlQuery -Session $Session -Sql "SELECT 1 FROM mysql.user WHERE User = $userStr AND Host = $ipStr LIMIT 1;" -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds))
    if ($existing.Count -gt 0) {
        return "Database user $account already exists. No changes made (use Grant Admin Privileges' optional password field to reset it)."
    }

    $secret = ConvertTo-OneLinkSqlString $Password
    $sql = "CREATE USER IF NOT EXISTS $account IDENTIFIED BY $secret;"
    Invoke-OneLinkDatabaseCommand -Session $Session -Command (New-OneLinkMysqlSqlCommand $sql) -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds) -Secrets @($Password) | Out-Null
    return "Database user $account created."
}

function Invoke-OneLinkCreateDatabase {
    param($Session, $Settings, [string]$DatabaseName)
    $identifier = ConvertTo-OneLinkDatabaseIdentifier $DatabaseName
    $nameStr = ConvertTo-OneLinkSqlString $DatabaseName

    $existing = @(Invoke-OneLinkMysqlQuery -Session $Session -Sql "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = $nameStr LIMIT 1;" -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds))
    if ($existing.Count -gt 0) {
        return "Database '$DatabaseName' already exists. No changes made."
    }

    Invoke-OneLinkDatabaseCommand -Session $Session -Command (New-OneLinkMysqlSqlCommand "CREATE DATABASE IF NOT EXISTS $identifier;") -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds) | Out-Null
    return "Database '$DatabaseName' created."
}

function Invoke-OneLinkGrantPrivileges {
    param($Session, $Settings, [string]$Username, [AllowEmptyString()][string]$AllowedIp, [string]$DatabaseName, [AllowEmptyString()][string]$Password)
    if ([string]::IsNullOrWhiteSpace($Username)) { throw 'Database username is required.' }
    $identifier = ConvertTo-OneLinkDatabaseIdentifier $DatabaseName
    $ip = if ([string]::IsNullOrWhiteSpace($AllowedIp)) { '%' } else { $AllowedIp.Trim() }
    $userStr = ConvertTo-OneLinkSqlString $Username.Trim()
    $ipStr = ConvertTo-OneLinkSqlString $ip
    $account = "$userStr@$ipStr"

    $existing = @(Invoke-OneLinkMysqlQuery -Session $Session -Sql "SELECT 1 FROM mysql.user WHERE User = $userStr AND Host = $ipStr LIMIT 1;" -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds))
    $userExisted = $existing.Count -gt 0

    # MySQL 8 no longer creates the user implicitly on GRANT - fail with a clear
    # reason up front rather than letting a raw SQL error bubble up.
    if (-not $userExisted -and [string]::IsNullOrEmpty($Password)) {
        throw "Database user $account does not exist yet. Enter a password to create the account as part of this grant, or create the user first via 'Create DB User'."
    }

    $sql = ''
    $passwordNote = ''
    if (-not [string]::IsNullOrEmpty($Password)) {
        $secret = ConvertTo-OneLinkSqlString $Password
        $sql = "CREATE USER IF NOT EXISTS $account IDENTIFIED BY $secret;`nALTER USER $account IDENTIFIED BY $secret;`n"
        $passwordNote = if ($userExisted) { ' (existing account - password updated)' } else { ' (new account created)' }
    }
    $sql += "GRANT ALL PRIVILEGES ON $identifier.* TO $account;"
    Invoke-OneLinkDatabaseCommand -Session $Session -Command (New-OneLinkMysqlSqlCommand $sql) -TimeoutSeconds ([int]$Settings.Ssh.CommandTimeoutSeconds) -Secrets @($Password) | Out-Null
    return "Granted privileges on '$DatabaseName' to $account$passwordNote."
}

# Both synchronous helpers and background transfer workers use these builders.
function New-OneLinkDatabaseExportCommand {
    param([string]$DatabaseName, [string]$FilePath)
    [void](ConvertTo-OneLinkDatabaseIdentifier $DatabaseName)
    if ($FilePath -notmatch '^/' -or $FilePath -match '[\r\n\x00]') { throw 'Backup path must be an absolute Linux file path.' }
    $header = (Get-OneLinkDatabaseShell) + "`ndb=" + (ConvertTo-OneLinkBashArg $DatabaseName) + "`noutFile=" + (ConvertTo-OneLinkBashArg $FilePath) + "`n"
    $body = @'
dump_client=$(command -v mysqldump || command -v mariadb-dump) || { echo 'Database dump client is not installed.' >&2; exit 1; }
umask 077
# Build the dump in /tmp (always writable by the connecting user) - the final
# destination directory (e.g. /mysqldata) is commonly root/mysql-owned and NOT
# writable by that user, so both the temp file AND the final copy must go
# through db_run (sudo). A plain '>' or 'mv' into that directory only carries
# the connecting user's own permissions, not sudo's, and fails with
# "Permission denied" even though db_run's mysqldump itself succeeds.
outDir=$(dirname -- "$outFile")
db_run mkdir -p -- "$outDir" 2>/dev/null || true
tmp=$(mktemp -- "${TMPDIR:-/tmp}/onelink-db-export.XXXXXX")
trap 'rm -f -- "$tmp" "${tmp}.gz"' EXIT
if ! db_run "$dump_client" --protocol=SOCKET --user=root --add-drop-table --skip-lock-tables --single-transaction --hex-blob --master-data=2 -- "$db" > "$tmp"; then
    db_run "$dump_client" --protocol=SOCKET --user=root --add-drop-table --skip-lock-tables --single-transaction --hex-blob -- "$db" > "$tmp"
fi
case "$outFile" in
    *.gz) gzip -c -- "$tmp" > "${tmp}.gz"; db_run cp -f -- "${tmp}.gz" "$outFile" ;;
    *) db_run cp -f -- "$tmp" "$outFile" ;;
esac
# The copy above runs as root (via db_run), leaving $outFile root-owned. That is
# invisible for a 'Server' destination (nothing reads it back through this
# session), but for Local/Network destinations this SAME file is immediately
# SCP'd down by the connecting (non-root) user - which then fails with
# "Permission denied" against a root:0600 file, even though every step up to
# here succeeded. Reclaim ownership for the connecting user BEFORE locking it
# down, so it stays private (0600) but is readable by whoever actually ran the
# export, on this box or over SCP.
me=$(id -un)
db_run chown -- "$me" "$outFile" 2>/dev/null || true
chmod 0600 -- "$outFile" 2>/dev/null || db_run chmod 0600 -- "$outFile" 2>/dev/null || true
echo "Database export completed."
'@
    return ConvertTo-OneLinkDatabaseCommand ($header + $body)
}

function New-OneLinkDatabaseImportCommand {
    param([string]$DatabaseName, [string]$FilePath)
    $identifier = ConvertTo-OneLinkDatabaseIdentifier $DatabaseName
    if ($DatabaseName -in @('mysql','sys','information_schema','performance_schema')) { throw 'Restoring over a system database is not supported.' }
    if ($FilePath -notmatch '^/' -or $FilePath -match '[\r\n\x00]') { throw 'Restore path must be an absolute Linux file path.' }
    $sql = "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'; DROP DATABASE IF EXISTS $identifier; CREATE DATABASE $identifier;"
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
    $header = (Get-OneLinkDatabaseShell) + "`ndb=" + (ConvertTo-OneLinkBashArg $DatabaseName) + "`nsqlFile=" + (ConvertTo-OneLinkBashArg $FilePath) + "`ncreateSql='$payload'`n"
    $body = @'
# The backup file (e.g. under /mysqldata) may be root/mysql-owned and NOT
# readable by the connecting user, even though db_run's sudo commands can read
# it fine. A plain 'test -r' / '<' redirect only carries the connecting user's
# own permissions (redirection happens in this shell, before sudo runs), so
# every touch of "$sqlFile" below goes through db_run instead.
db_run test -r "$sqlFile" || { echo 'Backup file is missing or not readable.' >&2; exit 1; }
db_run test -s "$sqlFile" || { echo 'Backup file is empty.' >&2; exit 1; }
case "$sqlFile" in *.gz) db_run gzip -t -- "$sqlFile" ;; esac
# Confirm database authentication BEFORE dropping the selected database.
db_mysql --execute='SELECT 1' >/dev/null
printf '%s' "$createSql" | base64 --decode | db_mysql
case "$sqlFile" in
    *.gz) db_run gzip -dc -- "$sqlFile" | db_mysql --database="$db" ;;
    *) db_run cat -- "$sqlFile" | db_mysql --database="$db" ;;
esac
echo 'Database import completed.'
'@
    return ConvertTo-OneLinkDatabaseCommand ($header + $body)
}

function Get-OneLinkDatabaseWorkerFunctions {
    $names = @('ConvertTo-OneLinkBashArg','ConvertTo-OneLinkDatabaseIdentifier','Get-OneLinkDatabaseShell','ConvertTo-OneLinkDatabaseCommand','New-OneLinkDatabaseExportCommand','New-OneLinkDatabaseImportCommand','New-OneLinkDatabaseJobCommand','ConvertTo-OneLinkWinArg','Invoke-OneLinkNetUse','New-OneLinkSqlScriptRunCommand')
    return (($names | ForEach-Object { 'function ' + $_ + " {`n" + (Get-Item "Function:$_").Definition + "`n}" }) -join "`n")
}
function New-OneLinkDatabaseJobCommand {
    param([string]$Command, [ValidatePattern('^[a-f0-9]{32}$')][string]$JobId)
    $dir = '/tmp/onelink-db-' + $JobId
    $body = 'set -euo pipefail; echo $$ > ' + (ConvertTo-OneLinkBashArg "$dir/pid") + "; trap 'rm -f -- " + "$dir/pid; rmdir -- $dir" + "' EXIT; " + $Command
    return 'umask 077; mkdir -- ' + (ConvertTo-OneLinkBashArg $dir) + ' && setsid bash -c ' + (ConvertTo-OneLinkBashArg $body)
}

function Invoke-OneLinkDatabaseServiceAction {
    param($Session, [ValidateSet('Restart','Stop')][string]$Action, [string]$Unit, [int]$TimeoutSeconds = 120)
    $verb = $Action.ToLowerInvariant()
    $scriptText = "set -e`n" + 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH' + "`n" +
        'if [ "$(id -u)" = 0 ]; then systemctl ' + $verb + ' ' + (ConvertTo-OneLinkBashArg $Unit) + '; else sudo -n systemctl ' + $verb + ' ' + (ConvertTo-OneLinkBashArg $Unit) + '; fi'
    Invoke-OneLinkDatabaseCommand -Session $Session -Command $scriptText -TimeoutSeconds $TimeoutSeconds | Out-Null
}
