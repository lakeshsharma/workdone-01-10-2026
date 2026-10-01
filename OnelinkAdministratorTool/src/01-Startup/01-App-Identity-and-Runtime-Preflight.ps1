#Requires -Version 5.1
[CmdletBinding()]
param()

# ============================================================================
#  TOOL NAME  -  change this ONE value to rename the whole application.
#  It drives the window title, the header, the footer, every popup/report
#  title, exported file names, etc. Nothing else needs to be edited to rename.
# ============================================================================
$script:AppName = 'Foreman'
# Short descriptor shown after the name in the footer AND in the header badge -
# change it once here and it updates in both places.
$script:AppTagline = 'OneLink Remote Administration'

# ============================================================================
#  OneLink Administration Tool
#  ---------------------------------------------------------------------------
#  SELF-CONTAINED / STANDALONE build with MULTI-SERVER support.
#
#  Everything that used to live in external files is embedded directly in this
#  single script:
#     - All PowerShell modules (ConfigManager, Logger, SshManager,
#       NMenuAutomation, PackageManager, OneLinkOperations)
#     - The WPF XAML user interface (was UI\MainWindow.xaml)
#     - The default JSON configuration (was Config\Settings.json and
#       Config\NMenuMappings.json)
#
#  Nothing is loaded from Modules\, UI\ or Config\ anymore.
#
#  Multi-server model:
#     - Build a list of target servers in a grid (Host + Port per row).
#     - "Same SSH credentials for all servers" -> enter one username/password.
#       Uncheck it to give every server its own username/password.
#     - "Connect All" opens an SSH session to every server in the list.
#     - Every operation has a "Target server" selector: run on ALL connected
#       servers or a single chosen server. When running on all servers a
#       failure on one server does not stop the rest; a per-server summary is
#       shown at the end.
#
#  The ONLY thing created/used beside the EXE at runtime is the Logs folder.
#  Optionally, an external "Settings.json" and/or "NMenuMappings.json" placed
#  next to the EXE overrides the embedded defaults.
#
#  Runtime requirement on the target machine: the Posh-SSH PowerShell module.
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    throw "This WPF application must be run on Windows."
}

# Many customer machines default to a Restricted execution policy, which blocks
# loading module script files such as Posh-SSH.psm1 ("running scripts is
# disabled on this system"). Relax the policy for THIS PROCESS ONLY - it needs
# no admin rights and writes nothing to the machine (nothing persists after the
# app closes) - so dependent modules can be imported. Wrapped in try/catch
# because a Group Policy that pins the Machine/User scope cannot be overridden
# by a process-scope change; in that case the connection step surfaces a clear
# error instead of the app failing to start.
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
}
catch {
    # Intentionally ignored.
}

