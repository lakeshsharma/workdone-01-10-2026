# OneLink Administration Tool ("Foreman") — Architecture Walkthrough

This document is written for the code-walkthrough meeting. It explains the
"why" behind the structure, not just the "what."

---

## 1. What the tool is, in one sentence

A single standalone Windows EXE that gives techs a GUI to manage OneLink
servers over SSH — connecting to multiple servers at once to run database
operations, deploy packages, manage certificates, and check service health —
without installing anything else on their machine.

---

## 2. The big picture: source code vs. shipped product

This is the most important thing to understand before looking at any file:

```
   src\  (40+ small .ps1 files, organized by feature)
      │
      │   Build.ps1  reads src\build-order.txt and concatenates
      │   every listed file, IN ORDER, byte-for-byte, into ONE file
      ▼
   OneLinkAdminTool.ps1   (single assembled script, ~1.8+ MB)
      │
      │   Build.ps1 then calls ps2exe to compile that single script
      ▼
   OneLinkAdministrationTool.exe   (what techs actually run)
```

**Why split the source at all, if it just gets glued back together?**
Because a single 5,000+ line .ps1 file is unreviewable and unmaintainable.
Splitting it by feature means:
- Each file is small enough to reason about on its own.
- Two people can work on different tabs (e.g. Database vs. Certificates)
  without merge conflicts.
- The folder structure IS the architecture diagram — you can understand
  the whole app just by reading folder/file names top to bottom.

**Why does order matter?**
PowerShell executes top to bottom. A function must be *defined* before
anything calls it. `Build.ps1` enforces this two ways:
1. `src\build-order.txt` lists every file in the exact order it must be
   glued together.
2. `Build.ps1` scans `src\` for any `.ps1` file NOT listed in
   `build-order.txt` and **fails the build** if it finds one — so a new
   file can never be silently left out of the EXE.

---

## 3. Folder-by-folder breakdown (execution order)

### `01-Startup` — bootstrapping, before any UI exists
| File | Purpose |
|---|---|
| `01-App-Identity-and-Runtime-Preflight.ps1` | Single place that defines the app's name (drives window title, footer, exported filenames, etc. — change once, updates everywhere) |
| `02-Embedded-PoshSSH-Payload.ps1` | Just holds the giant base64 string — the entire Posh-SSH module packed as a zip, so the tool is a true single-file EXE |
| `03-PoshSSH-Extraction-and-Import.ps1` | On first run: use Posh-SSH if already installed on the machine, otherwise decode/unzip the embedded copy to `%LOCALAPPDATA%` and load it |
| `04-Windows-Assemblies-Roles-and-Data-Models.ps1` | Loads the .NET assemblies the app needs (WPF, Windows Forms, Compression) and defines the core data model (server roles, etc.) |

### `02-Embedded-Resources` — what the app looks like
| File | Purpose |
|---|---|
| `01-Base-Directory-and-Default-Configuration.ps1` | Where the EXE lives on disk; default config used if no external Settings.json is present |
| `02-Main-Window-Layout-Xaml.ps1` | The entire WPF UI (tabs, buttons, grids, colors) defined as XAML text, loaded at runtime by `XamlReader` |

### `03-Core-Services` — cross-cutting infrastructure
| File | Purpose |
|---|---|
| `01-Configuration-Loader.ps1` | Reads/writes `Settings.json` and similar config |
| `02-Logging-and-User-Preferences.ps1` | Application logging + remembered user preferences |
| `03-Efficiency-Log-and-Activity-Recorder.ps1` | A separate CSV log tracking how long each operation (install, backup, etc.) took — used for reporting, not troubleshooting |

### `04-Remote-Operations` — the actual "doing things to servers" logic
This is the functional core of the tool — everything here runs commands
*on the remote OneLink servers* via SSH.

| File | Purpose |
|---|---|
| `01-SSH-Session-Management.ps1` | Open/close SSH sessions, run remote commands (built on Posh-SSH) |
| `02-Database-Operations.ps1` | Shared safe shell-quoting helpers + direct MySQL operations |
| `03-Service-SSL-and-Certificate-Operations.ps1` | Start/stop services and certificate operations (systemctl on RHEL, service on Debian — OS-aware) |
| `04-Package-Upload-and-Install.ps1` | Upload and install OneLink packages onto target servers |
| `05-Service-Discovery-and-OS-Detection.ps1` | Detect what OS/services a target server is running |

### `05-Main-Window-Setup` — connecting the UI to the logic
| File | Purpose |
|---|---|
| `01-Window-Load-and-Control-Binding.ps1` | Loads config, loads the XAML window, binds named controls to variables |
| `02-Runtime-State-and-Log-Initialization.ps1` | Defines the in-memory "connected servers" state (host, credentials, session, status per server) |
| `03-Activity-Capture-Hooks-and-Footer-Controls.ps1` | Wires up activity tracking for the footer/metrics panel |

### `06-UI-Common` — reusable UI building blocks
Message dialogs, a generic "edit any remote file" popup (reads with sudo,
transfers as base64 so special characters survive), an SSH command console
(a plain textbox, not a full terminal — so `vim`/`top` won't render, but
ordinary command output stays readable), and misc UI helpers.

### `07-Server-Inventory` — the server list / grid (the hub of the app)
Adding/editing servers, per-row credentials, connect/disconnect, live
health checks, multi-select target pickers used by every other tab, and
running one operation across multiple selected servers at once with a
per-server summary at the end.

### `08-Configuration-Import-Export` — save/load setup as a file
Exports/imports tool configuration as CSV/XLSX. **Deliberately excludes**
server IPs, credentials, and passwords from the export — only default
field values and form settings travel in the file; a re-imported server
list arrives with blank passwords the user must re-enter.

### `09-Database-Tab` — MySQL/MariaDB operations
Service control, InnoDB buffer pool sizing (mirrors the legacy `nmenu`
tool's logic: 75% of RAM, rounded to nearest 128MB), running arbitrary
`.sql` scripts, user/database/grant creation, and backup/restore. Backup
jobs run as background jobs (via a `DispatcherTimer`) so the UI stays
responsive during multi-hour dumps, with a Stop button and up to a
36-hour timeout ceiling (configurable).

### `10-Package-Tab` — deploying OneLink packages
Matches packages in a folder to server roles by filename pattern,
installs them, checks for version downgrades, and reports per-service
install status/details.

### `11-Certificates-Tab`
Certificate deployment, scanning, and status reporting across servers.

### `12-Application-Lifecycle`
Exporting logs/metrics as CSV reports, and app startup/shutdown/global
error handling.

---

## 4. Key architectural decisions (the "why" questions you'll get asked)

**Q: Why WPF/XAML instead of plain PowerShell forms?**
WPF gives a modern, styled UI (colors, layout flexibility) that WinForms
can't easily match. The layout is written once as XAML (markup, like HTML
for desktop apps) and loaded at runtime by .NET's `XamlReader` — PowerShell
never "understands" XAML, it just hands the text to .NET and gets real
window objects back.

**Q: Why is Posh-SSH embedded as a giant base64 string instead of required
as a prerequisite?**
Posh-SSH is a third-party module, not built into Windows — PowerShell has
no native SSH support. Requiring `Install-Module Posh-SSH` on every tech's
machine would mean depending on internet access, PowerShell Gallery
access, and sometimes admin rights. Embedding it means the EXE works
out-of-the-box, offline, on any Windows machine — the embedded copy is
only extracted as a *fallback* if Posh-SSH isn't already present (see
`04-Remote-Operations\01-SSH-Session-Management.ps1`).

**Q: What does the compiled EXE download on a fresh Windows machine?**
Nothing. The .NET assemblies it uses (PresentationFramework,
System.Windows.Forms, System.IO.Compression) ship with every Windows
install. Posh-SSH is embedded, not downloaded. Internet/module installs
(`Install-Dependencies.ps1`, `ps2exe`) are only ever needed on the
*build* machine — never on an end user's machine.

**Q: Why is a version pinned for the embedded Posh-SSH (3.2.3)?**
So behavior is identical and reproducible across every machine the tool
runs on, regardless of whether — or what version — that machine already
has installed.

**Q: Why exclude passwords/IPs from config export?**
Security — the exported config file is meant to be shareable (e.g. for
setting up the tool on a new machine) without leaking credentials.

---

## 5. Suggested walkthrough order for the meeting

1. One-sentence pitch of what the tool does
2. Show the running app briefly — tabs = features
3. Explain the source→EXE build pipeline (section 2 above)
4. Walk the folder structure in order (section 3) — this doubles as the
   app's execution flow
5. Posh-SSH: what it is, why embedded, correct any "every Windows has an
   SSH client" assumption — it doesn't
6. Q&A using section 4 as prep
