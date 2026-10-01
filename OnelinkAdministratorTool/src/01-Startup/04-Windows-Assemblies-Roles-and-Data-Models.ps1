Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
# Loaded unconditionally so the .xlsx config engine's ZipArchive / ZipArchiveMode
# (System.IO.Compression) and ZipFile (…FileSystem) always resolve - not just when
# the embedded Posh-SSH is being extracted. Both ship with .NET Framework 4.5+ (no
# new dependency); this only makes the types available in the session.
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# ============================================================================
#  Server row model + role marks
# ============================================================================
#  The six fixed roles a VM (IP) can be marked with. A single IP may carry more
#  than one role (e.g. AppServer + Concentrator on the same host).
#  'Auxiliary Service' is for NON-OneLink packages/apps (nginx, postgresql, a
#  custom rpm/deb, etc.): installed like any package but with NO SSL step, and its
#  systemd unit(s) are AUTO-DISCOVERED (not a fixed onelink-* name) so they can be
#  started/restarted/stopped via plain systemctl. It never touches the OneLink role
#  logic (RoleServiceMap / RolePackageName / SSL) - it is simply absent from those.
$script:OlRoles = @('AppServer','Concentrator','ReportServer','nConnect','WebEvents','Database master','Database slave','Auxiliary Service')

# Maps a role mark to the systemd service that role runs. Used by the Services
# tab so restart/stop/status act on the services an IP is marked for (the
# package for AppServer is 'onelink' but its service is 'onelink-appserver').
# Database roles have no OneLink service and are intentionally omitted.
$script:RoleServiceMap = [ordered]@{
    'AppServer'    = 'onelink-appserver'
    'Concentrator' = 'onelink-concentrator'
    'ReportServer' = 'onelink-report-server'
    'nConnect'     = 'onelink-nconnect'
    'WebEvents'    = 'onelink-webevents'
}

# One editable row in the Server grid. A real class (not a PSCustomObject) so
# WPF two-way binding on IP/Port/Username writes back reliably. Status/Roles/
# password-display change programmatically and are refreshed via Items.Refresh().
class OlServer {
    [string]$Host = ''
    [int]$Port = 22
    [string]$Username = ''
    [string]$Roles = ''
    [string]$RolesDisplay = 'Select...'
    [string]$PasswordDisplay = 'Set...'
    [string]$Status = 'Not connected'
    [string]$ServicesDisplay = '-'
    [string]$Os = ''
    [object]$SecurePassword = $null
    [object]$Session = $null
    [object]$Credential = $null
    [object]$Services = $null
    [object]$AuxServices = $null   # discovered non-OneLink systemd units (Auxiliary Service role); $null = not yet discovered
    [string]$Health = 'View'       # resource health: View (unknown) / OK / CAUTION / CRITICAL - drives the Resources button colour (via DataTriggers)
    [string]$HealthNote = ''       # short summary e.g. "Disk /var 88% - Mem 72%"

    OlServer() {
        $this.Services = New-Object System.Collections.Generic.List[object]
    }

    # Roles as an array (splits the comma-separated display string).
    [string[]] RoleList() {
        if ([string]::IsNullOrWhiteSpace($this.Roles)) { return @() }
        return @($this.Roles -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    [bool] HasRole([string]$role) {
        return ($this.RoleList() -contains $role)
    }
}

# One recorded activity (a completed user task): how many clicks/fields it took
# and how long, for the Activity Metrics tab. Plain class so WPF binding is clean.
class OlActivityMetric {
    [string]$Time = ''
    [string]$Activity = ''
    [string]$Target = ''
    [string]$Outcome = ''
    [int]$Clicks = 0
    [int]$Inputs = 0
    [double]$ActivitySeconds = 0
    [double]$OperationSeconds = 0
}

# One row in the Package deployment plan: which package goes to which server
# for a given role. Package is editable in the grid (a dropdown of Available).
class OlPlanRow {
    [string]$Host = ''
    [string]$Role = ''
    [string]$Package = ''
    [string]$Size = ''
    [string]$Status = 'Planned'
    [object]$Available = @()
    [object]$Server = $null
}

