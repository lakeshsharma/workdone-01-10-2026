# Cycode-Stats

Desktop dashboard that pulls open Cycode violations per studio and builds an
Excel report. Fully self-contained: the `cycode` CLI itself is bundled
*inside* `Cycode-Stats.exe`, so colleagues you share it with need **nothing**
pre-installed — no Python, no pip, no separate Cycode CLI. Just the one exe.

## Using it (for anyone you share the exe with)

1. Run `Cycode-Stats.exe`.
2. **Tab 1 — Studios & Fetch**: first time on a machine, click
   **🔑 Sign in to Cycode**. This opens your browser to Cycode's normal
   login page (same flow as `cycode auth`); log in, and the app saves your
   credentials to `%USERPROFILE%\.cycode\credentials.yaml` — a genuine
   one-time step per machine, not per run.
3. Pick a studio and click **Fetch violations**.
4. **Tab 2 — Scope**: pick one branch per repo (click the Branch cell when
   a repo has more than one, just to preview its stats), toggle **Include**
   to decide which repos count toward the report, then **Save scope**.
5. **Tab 3 — Generate Report**: click **Generate Excel** →
   two independent reports you can tick either or both of:
   - **Scoped report** (`<Studio>_CycodeReport_Scoped_<date>.xlsx`) — only
     repos ticked Include on Tab 2, each at the branch picked there.
   - **All repos & all branches report** (`<Studio>_CycodeReport_All_<date>.xlsx`)
     — everything fetched, ignoring Scope, with two sheets: **Repository
     Summary** (every branch summed per repo) and **Branch Summary** (one
     row per repo+branch).

Studios ship seeded with `OneLink` → project 36416 and `System7000` →
project 25214. Add more (Oasis, Loyalty, etc.) via **⚙ Manage Studios** on
Tab 1 — you just need that studio's Cycode project id (the id used in the
Cycode dashboard URL).

## How the "no dependencies" part works

`cycode` is a normal PyPI package under the hood. Instead of shelling out to
a separately-installed `cycode.exe` (which is what the original
`cycode_system7000_report.py` script did, and why it broke on machines
without it), this app imports `cycode` as a library and invokes its own
Click commands **in-process** (`app/cycode_cli.py`), then PyInstaller bundles
the whole `cycode` package into the one exe (`--collect-all cycode` in
`build_exe.bat`). Auth is likewise driven in-process
(`cycode.cli.apps.auth.auth_manager.AuthManager`) from the Sign In button,
rather than requiring a terminal.

## Data files

Everything lives next to the exe in `data\`:
- `studios.json` — studio name → Cycode project id (editable via Manage Studios).
- `scope_<studio>.csv` — your saved branch/include choices per studio.
- `catalogue_<studio>.json` — the last fetch result per studio (used to
  populate the app instantly on restart without re-fetching).

`output\` holds the generated Excel reports. Cycode's own credentials file
is separate, at `%USERPROFILE%\.cycode\credentials.yaml`.

## Rebuilding the exe from source

```
build_exe.bat
```
This creates an isolated `.venv` in this folder on first run (installing
`cycode`, `openpyxl`, `pyinstaller` there — **never** into your system
Python) and produces `dist\Cycode-Stats.exe`.

Run `run.bat` to launch from source without building (also uses the local
`.venv`), during development.

**Do not** `pip install cycode` (or anything else this project needs)
directly into your system/global Python — it drags in a large, unrelated
dependency tree (GitPython, jsonschema, typer, the `mcp` SDK, etc.) that can
silently upgrade shared packages other tools on your machine rely on. Always
go through `build_exe.bat` / `run.bat`, which keep everything inside this
project's own `.venv`.
