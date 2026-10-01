# OneLink Administration Tool

A **self-contained** PowerShell WPF application for remotely executing common
OneLink administration tasks over SSH.

Everything the application needs (all former modules, the WPF interface, and the
default JSON configuration) is now embedded directly inside a single script,
`OneLinkAdminTool.ps1`. When compiled with PS2EXE the result is a single
`OneLinkAdministrationTool.exe` that can be copied to any Windows PC on its own.

## Included operations

- Test and establish SSH connectivity
- Create a MySQL user through `nmenu`
- Create a OneLink database through `nmenu`
- Grant database privileges through `nmenu`
- Upload a package (`.rpm`, `.deb`, or any type you configure) using SCP
- Install or upgrade a package - the packager is auto-detected from the file
  extension (`.rpm` -> rpm/RHEL, `.deb` -> dpkg/Debian) and runs unattended
- Restart or stop a OneLink service (via nmenu's `nstart` / `nstop`)
- Check service status (via nmenu's `nstatus`)
- Enable or disable SSL for Concentrator or Report Server (via `n_ssl_config`)
- Check remote service status
- Write sanitized activity logs

## Multi-server usage

The tool manages many servers at once:

1. **Add servers** — enter a Host and Port and click **Add Server**; each server
   appears as a row in the server list. Remove rows with **Remove Selected**.
2. **Credentials** — leave **"Same SSH credentials for all servers"** checked to
   enter one username/password used for every server. Uncheck it to type a
   separate username/password on each **Add Server** (each server keeps its own).
3. **Connect All** opens an SSH session to every server in the list; the grid
   shows a per-server status (including whether `nmenu` was found). A server
   that fails to connect does not stop the others.
4. **Run operations** — every operation has a **Target server** selector. Choose
   **All servers** to run on every connected server, or pick one specific server.
   When running on all servers, a failure on one does not stop the rest; a
   per-server success/failure summary is shown at the end.

### Service discovery

The **Service** list on the *Services and SSL* tab is discovered from the
connected servers rather than hardcoded:

- On **Connect All**, each server is queried (`systemctl list-unit-files`) for
  services matching `Remote.ServiceUnitPattern` (default `onelink-*.service`).
- The Service dropdown shows the **union** of services found across all
  connected servers. Before you connect, it previews the configured list.
- **Check Service Status** works for any discovered service (it uses systemd).
- **Start / Restart** run through `nmenu`, so they are enabled only for services
  that have a key under `Services.ServiceKeys` in `NMenuMappings.json`. A
  discovered service without a key is status-only (the button is disabled with a
  tooltip explaining why).
- When you run a service action on **All servers**, servers that do not have the
  selected service are **skipped** (and listed in the summary), not failed.

## Architecture (standalone)

There is only one source file. It contains, as embedded sections:

- All former modules — `ConfigManager`, `Logger`, `SshManager`,
  `NMenuAutomation`, `PackageManager`, `OneLinkOperations`
- The WPF interface (previously `UI/MainWindow.xaml`) as an embedded here-string
- The default configuration (previously `Config/Settings.json` and
  `Config/NMenuMappings.json`) as embedded here-strings

Nothing is loaded from `Modules/`, `UI/`, or `Config/` at runtime. Those folders
are no longer required and may be left behind in the source tree for reference
only — they are not read by the application or the compiled EXE.

```text
Source tree (development)          Distribution (runtime)
---------------------------        ----------------------------------
OneLinkAdminTool.ps1               OneLinkAdministrationTool.exe
Install-Dependencies.ps1           Logs/                (created automatically)
README.md                          Settings.json        (OPTIONAL override)
                                   NMenuMappings.json   (OPTIONAL override)
```

## Runtime configuration

The application always ships with working defaults baked in. Overrides are
optional:

- On startup it looks for **`Settings.json`** beside the EXE. If present it is
  loaded; otherwise the embedded defaults are used.
- The same applies to **`NMenuMappings.json`** beside the EXE.

This lets you tweak SSH ports, the remote upload directory, service lists, or
`nmenu` key/prompt mappings on a specific machine without recompiling — but it
is never required for the tool to run.

The **`Logs`** folder is the only artifact created on disk. It is created
automatically beside the EXE the first time the tool runs.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7 on Windows (only needed to compile;
  the compiled EXE bundles its own runtime host)
- **Posh-SSH** is **embedded in the EXE** — it does not need to be installed on
  the machine that runs the tool. On first run, if the machine does not already
  have Posh-SSH, the bundled copy is extracted to
  `%LOCALAPPDATA%\OneLinkAdminTool\Modules` (per-user, no admin).
- SSH access to the target Linux machine
- `nmenu` installed and available to the connected account
- Appropriate sudo rights for package and service operations

## Building the standalone EXE

Install PS2EXE (once) and the SSH dependency:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Install-Module -Name ps2exe -Scope CurrentUser -Force
.\Install-Dependencies.ps1
```

Compile. **Recommended** - use the bundled build script, which verifies the
embedded Posh-SSH blob is present (guards against a stale/old source file),
imports ps2exe even when it lives under OneDrive-redirected Documents, and
sanity-checks the output size:

```powershell
.\Build.ps1
```

Or compile directly (works when ps2exe is already imported in your session):

```powershell
Invoke-PS2EXE `
    -InputFile .\OneLinkAdminTool.ps1 `
    -OutputFile .\OneLinkAdministrationTool.exe `
    -NoConsole `
    -STA
```

> The source file is ~1.8 MB because Posh-SSH is embedded in it. A correctly
> built EXE is **≥ 1.5 MB**. If your EXE is only a few hundred KB, it was compiled
> from stale source - rebuild with `.\Build.ps1`.

## Distribution

Copy **only** `OneLinkAdministrationTool.exe` to the target Windows PC. On first
launch it creates a `Logs` folder beside itself. No `Modules/`, `UI/`, or
`Config/` folders are needed.

> **Posh-SSH is bundled inside the EXE**, so the customer does not need to
> install anything. On first connect, if the machine lacks Posh-SSH, the tool
> extracts its embedded copy to `%LOCALAPPDATA%\OneLinkAdminTool\Modules` and
> imports it (per-user, no admin, works offline). If the machine already has
> Posh-SSH, that copy is used instead.

### SmartScreen ("Windows protected your PC")

The EXE is **not code-signed**, so when it is copied to another PC (download,
email, network share) Windows tags it with a "mark of the web" and SmartScreen
shows *"Windows protected your PC → More info → Run anyway."* This is expected
for an unsigned executable and is not a fault in the tool. Options:

- **Proper fix:** sign the EXE with a code-signing certificate (an EV
  certificate clears SmartScreen immediately). This is an organisation/IT step.
- **Per-recipient workaround:** right-click the EXE → **Properties** → tick
  **Unblock** → OK, then run. Or run `Unblock-File .\OneLinkAdministrationTool.exe`.

### Execution policy

Windows client machines often default to a **Restricted** execution policy,
which blocks loading module script files and produces errors such as
*"Posh-SSH.psm1 cannot be loaded because running scripts is disabled on this
system."* The EXE handles this automatically: at startup it relaxes the policy
for its own process only (`Set-ExecutionPolicy -Scope Process Bypass`), which
needs no admin rights and persists nothing on the machine.

The only situation this cannot fix is when a **Group Policy** pins the policy at
the Machine or User scope (a process-scope change cannot override Group Policy).
That is an environment/IT setting, not something the tool can change; if you hit
it, the connection step reports a clear error and IT must adjust the policy.

Optionally, drop an editable `Settings.json` (and/or `NMenuMappings.json`)
beside the EXE to override the embedded defaults on that machine.

## Configuration reference

### `Settings.json` (embedded default; optional external override)

Contains:

- SSH port and timeouts
- Remote upload directory
- `nmenu` command
- Logging directory
- Default service list
- Service discovery pattern (`Remote.ServiceUnitPattern`)
- Package handling (`Packages`):
  - `Types.<ext>.Install` / `Types.<ext>.Upgrade` - command template per file
    extension (`{0}` is the remote package path). Add an entry here to support
    another package type/extension.
  - `AutoAnswer` - text fed to any interactive install prompt (via `yes`), which
    also presses Enter repeatedly so installs run unattended. Leave empty to
    just press Enter; set a value (e.g. a reason string) if a prompt needs one.

### `NMenuMappings.json` (embedded default; optional external override)

Contains:

- Menu keys
- Prompt regular expressions
- Service-selection keys
- SSL-selection keys
- Success-message patterns

Update these mappings to match the exact output and key assignments of your
installed `nmenu`.

## Security notes

- Passwords are not written to the log.
- SSH passwords remain in memory only for the current session.
- Database passwords sent to the remote terminal are masked in the GUI log.
- Host keys are accepted automatically only when `AcceptNewHostKey` is enabled.
- For production usage, consider replacing password authentication with SSH keys.

## Important validation requirement

`nmenu` installations can differ between versions. Before production use, verify:

1. Main menu key assignments.
2. Database submenu key assignments.
3. Exact prompt text.
4. Service selection keys.
5. SSL selection keys.
6. Whether `nmenu` uses `dialog`, `whiptail`, or plain terminal prompts.

If the installed `nmenu` uses full-screen `dialog` or `whiptail`, key navigation
may require configurable arrow, tab, space, or escape sequences. The current
implementation is designed primarily for letter-based menu selection and
prompt-driven input.
