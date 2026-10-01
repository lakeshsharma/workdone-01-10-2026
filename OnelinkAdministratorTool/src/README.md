# Foreman (OneLink Administration Tool) — Source Layout

The application used to be one 8,497-line script (`OneLinkAdminTool.ps1`). It is now split into
**43 small, purpose-named files** under this `src\` folder.

> **Nothing inside the files was changed.** The split only moved existing lines into separate files.
> Joining the files back together (in the order listed in `build-order.txt`) reproduces the original
> `OneLinkAdminTool.ps1` **byte for byte** — verified by SHA-256 (see [Verification record](#verification-record)).
> Behaviour, features and the standalone-EXE output are unchanged.

---

## Daily workflow

| I want to… | Do this |
|---|---|
| Change code | Edit the relevant file under `src\` (use the table below to find it) |
| Run / test the script directly | `.\Build.ps1 -AssembleOnly` then run `OneLinkAdminTool.ps1` (STA PowerShell) |
| Build the standalone EXE | `.\Build.ps1` (assembles the parts, verifies, then compiles with PS2EXE — as before) |
| Add a new file | Create it under the right folder **and add its path to `build-order.txt`** (the build stops and names any `.ps1` that is missing from the list) |

**Rules**

1. **Edit `src\` only.** `..\OneLinkAdminTool.ps1` is now a *generated* file — every build overwrites it. (It is kept in place because `Tests\` and the old workflow read it.)
2. **Order matters.** PowerShell runs the script top to bottom, so a function/class/variable must appear *before* the first line that uses it at start-up. The numbered folders/files and `build-order.txt` are the execution order. Don't reorder without a reason.
3. **Keep the encoding.** Part files are UTF-8 **with BOM** and **CRLF** line endings (`.editorconfig` enforces this in most editors). The build strips each part's BOM and writes a single BOM at the top of the assembled file.
4. **Each file is complete PowerShell** (whole functions / whole statements) and parses on its own, so editors and analyzers work per file. Exception to "open it in an editor": see the payload file below.

---

## File index (execution order)

### 01-Startup — process start-up, before any UI exists
| File | Lines | Purpose |
|---|---:|---|
| `01-App-Identity-and-Runtime-Preflight.ps1` | 68 | `#Requires`/`param()`, the **one place to rename the app** (`$script:AppName`, tagline), strict mode, error preference, Windows-only guard, process-scope execution-policy relaxation |
| `02-Embedded-PoshSSH-Payload.ps1` | 14 | The Posh-SSH module embedded as a base64 zip (**1.6 MB on a single line — generated data; do not edit or open in a normal editor**) |
| `03-PoshSSH-Extraction-and-Import.ps1` | 52 | Extracts the embedded module to `%LOCALAPPDATA%\OneLinkAdminTool\Modules` on first run and imports it |
| `04-Windows-Assemblies-Roles-and-Data-Models.ps1` | 93 | Loads WPF / WinForms / Zip assemblies; server **roles** and role→service map; the `OlServer`, `OlActivityMetric`, `OlPlanRow` classes |

### 02-Embedded-Resources — data compiled into the EXE
| File | Lines | Purpose |
|---|---:|---|
| `01-Base-Directory-and-Default-Configuration.ps1` | 137 | Resolves the base directory; embedded default **Settings JSON** and **NMenu-mappings JSON** |
| `02-Main-Window-Layout-Xaml.ps1` | 1,464 | The whole **WPF window layout** as XAML: styles/brushes, header, server grid, Database / Certificates / Package / Metrics tabs, activity log, footer |

### 03-Core-Services — logging, config, metrics (no UI wiring)
| File | Lines | Purpose |
|---|---:|---|
| `01-Configuration-Loader.ps1` | 44 | Loads JSON configuration (embedded default, optional external override) |
| `02-Logging-and-User-Preferences.ps1` | 97 | Log file writer, secret masking in logs, `preferences.json` (e.g. chosen log folder) |
| `03-Efficiency-Log-and-Activity-Recorder.ps1` | 310 | Efficiency CSV, activity metrics (clicks / fields / active time), recorder on/off, capture dialog |

### 04-Remote-Operations — everything that talks to the servers
| File | Lines | Purpose |
|---|---:|---|
| `01-SSH-Session-Management.ps1` | 174 | Credentials, connect / test / disconnect, friendly SSH errors, command execution (CRLF→LF chokepoint), shell stream |
| `02-Database-Operations.ps1` | 244 | Bash/SQL quoting, MySQL root-socket shell, base64 command transport, create user / database / grant, export & import command builders |
| `03-Service-SSL-and-Certificate-Operations.ps1` | 257 | Service start/stop/status, SSL enable/disable (Concentrator, Report Server, AppServer), certificate install |
| `04-Package-Upload-and-Install.ps1` | 181 | Remote upload directory, SCP upload, RPM/DEB install |
| `05-Service-Discovery-and-OS-Detection.ps1` | 122 | Service-name mapping and status, service discovery, RHEL/Debian detection |

### 05-Main-Window-Setup — turning the XAML into a live window
| File | Lines | Purpose |
|---|---:|---|
| `01-Window-Load-and-Control-Binding.ps1` | 64 | Loads settings/mappings, builds the window from the XAML, binds every named control to a variable, title & icon |
| `02-Runtime-State-and-Log-Initialization.ps1` | 54 | Server / package collections, target-picker registry, default field values, log / efficiency / metrics initialisation |
| `03-Activity-Capture-Hooks-and-Footer-Controls.ps1` | 110 | Mouse/keyboard interaction capture, grid-edit hooks, HUD timer, Metrics-tab visibility, *Efficiency Recorder* and *Log Folder* buttons |

### 06-UI-Common — reusable windows and helpers
| File | Lines | Purpose |
|---|---:|---|
| `01-Message-Dialogs-and-Report-Window.ps1` | 111 | Error/info/warning boxes, header brush, styled report window |
| `02-Remote-File-Editor.ps1` | 537 | Built-in remote **File Editor** (find, load, edit, save) |
| `03-SSH-Command-Console.ps1` | 318 | Built-in **SSH Console** (ANSI stripping, interactive-command guard) |
| `04-UI-Common-Helpers.ps1` | 81 | Combo text, secure-string conversion, grid refresh, Posh-SSH availability check |

### 07-Server-Inventory — the server grid and multi-server actions
| File | Lines | Purpose |
|---|---:|---|
| `01-Target-Pickers-and-Service-Checklist.ps1` | 310 | Multi-select target pickers, auxiliary-service discovery, service checklist (search / select-all) |
| `02-Multi-Server-Operation-Runner.ps1` | 92 | `Invoke-MultiServerOperation` — runs an action across the selected servers with logging & timing (used by most tabs) |
| `03-Server-Grid-Editing-Credentials-and-Roles.ps1` | 253 | Add / remove rows, *Same login for all*, password and roles dialogs |
| `04-Server-Health-and-Resources.ps1` | 147 | Per-server service refresh, health status (disk / RAM), *Resources* popup |
| `05-Server-Grid-Events-and-Context-Menu.ps1` | 164 | In-grid button clicks and the right-click context menu |
| `06-Server-Connect-and-Disconnect.ps1` | 146 | Commit edits, *Connect All* / per-server connect (incl. passwordless-sudo bootstrap), *Disconnect* |

### 08-Configuration-Import-Export — settings ⇄ Excel
| File | Lines | Purpose |
|---|---:|---|
| `01-Config-Fields-and-XLSX-Engine.ps1` | 326 | Which fields are saved, the built-in `.xlsx` writer/reader, sheet definitions |
| `02-Config-Export-Import-Template-Buttons.ps1` | 193 | *Export*, *Template* and *Import* button handlers |

### 09-Database-Tab
| File | Lines | Purpose |
|---|---:|---|
| `01-MySQL-Service-Control.ps1` | 161 | MySQL enable / restart / stop / status (RHEL first-time setup), `Invoke-OneLinkMysqlQuery` |
| `02-InnoDB-Buffer-Pool.ps1` | 232 | InnoDB buffer-pool check (75 % of RAM guard) and apply with backup/rollback |
| `03-Run-SQL-Script.ps1` | 285 | Search a server for `.sql` files and run one in the background with a progress window and error hints |
| `04-Create-User-Create-Database-and-Grant.ps1` | 116 | Allowed-IP dropdown, *Create DB User*, *Create Database*, *Refresh lists*, *Grant Admin Privileges* |
| `05-Backup-Restore-Browse-Controls.ps1` | 56 | Backup timeout setting and the Browse / destination controls for export & import |
| `06-Background-Job-Runner.ps1` | 122 | Shared background-job infrastructure (start / watch / stop) used by backup, restore and SQL run |
| `07-Database-Backup-and-Restore.ps1` | 231 | Export and import workers (Server / Local / Network / another VM) and their buttons |

### 10-Package-Tab
| File | Lines | Purpose |
|---|---:|---|
| `01-Package-Plan-and-Network-Share-Access.ps1` | 245 | Package-to-role matching, network-share login/test (`net use` wrapper), package sizes, *Build Plan* |
| `02-Package-Deployment-Engine.ps1` | 209 | Role→package names, installed-version lookup, downgrade guard, enable/start, `Invoke-OneLinkPackageDeployment` |
| `03-Package-Tab-Button-Handlers.ps1` | 62 | Browse / Build / Remove / Clear / Upload / Upload-and-Install and service-list buttons |
| `04-Service-Installer-Control-and-Details.ps1` | 226 | Service Installer: restart / stop / status and *Check Details (version)* |

### 11-Certificates-Tab
| File | Lines | Purpose |
|---|---:|---|
| `01-Certificate-Deploy-Scan-and-Status.ps1` | 284 | Browse & deploy certificates, content-aware certificate scan, *List files*, *Check Status* |

### 12-Application-Lifecycle
| File | Lines | Purpose |
|---|---:|---|
| `01-Log-and-Metrics-Export-Buttons.ps1` | 43 | *Clear log*, *Open log*, metrics export / clear |
| `02-Startup-Shutdown-and-Error-Handling.ps1` | 62 | Window-closing cleanup, initial refresh calls, global unhandled-exception safety nets, `ShowDialog()` |

> Some files hold shared helpers that sit where they do only because of run order (for example
> `07-Server-Inventory\02-Multi-Server-Operation-Runner.ps1` and `09-Database-Tab\06-Background-Job-Runner.ps1`
> are used by several tabs). They were deliberately **not** moved, so execution order stays identical.

---

## Other folders in the project (untouched)

`Config\`, `Modules\`, `UI\` are the legacy external copies of what is now embedded in the script.
They were left exactly as they were — `Config\Settings.json` / `NMenuMappings.json` can still act as
optional overrides at run time, so do not delete them.

---

## Verification record

Split performed 2026-09-20 from `OneLinkAdminTool.ps1` (8,497 lines, 2,140,822 bytes).

* Reassembling the 43 parts with `Build.ps1 -AssembleOnly` gives a file with **SHA-256
  `DEC8271523FE1CC156DD82D6652A9BA38F2530563DAE0B5DCE8D7257BCB15DBC`** — identical to the original, under both
  Windows PowerShell 5.1 and PowerShell 7.
* Every part parses on its own with zero errors under both engines (cuts fall only on top-level statement boundaries).
* A full `Build.ps1` run (assemble → check → PS2EXE) produced a working EXE from the parts. EXEs from the same
  source differ run-to-run by PS2EXE build stamps, so compare the **script** hash, not the EXE hash.
* To re-check at any time *before* you start editing: run `.\Build.ps1 -AssembleOnly` and compare
  `Get-FileHash .\OneLinkAdminTool.ps1` with the hash above.
