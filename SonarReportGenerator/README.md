# SonarQube Vulnerability Reporter

One-click desktop tool (Python + Tkinter) that pulls SonarQube vulnerability
stats for Aristocrat studios, produces the quarterly Excel report in your
template format, and drafts the Outlook mail — replacing the manual work.

## Run it (one-click)

**Easiest — just double-click** `run.bat` in
`C:\Users\LS112622\Downloads\OneLinkAdminTool\SonarVulnReporter`.
First launch installs dependencies, then the window opens.

### Exact commands

Open **Command Prompt (cmd)** *or* **PowerShell** (a normal terminal — not the
PowerShell ISE, which is only for editing scripts) and run:

**cmd:**
```
cd C:\Users\LS112622\Downloads\OneLinkAdminTool\SonarVulnReporter
run.bat
```

**PowerShell:**
```
cd C:\Users\LS112622\Downloads\OneLinkAdminTool\SonarVulnReporter
.\run.bat
```

### Build a single .exe (to share, no Python needed on the other PC)

Double-click `build_exe.bat`, or run:
```
cd C:\Users\LS112622\Downloads\OneLinkAdminTool\SonarVulnReporter
build_exe.bat
```
This produces **`dist\SonarVulnReporter.exe`**. Double-click that exe to run —
it creates a writable `data\` folder next to itself on first launch (seeded
from the bundled studio list). One-click, self-contained.

> Tip: right-click `SonarVulnReporter.exe` → *Send to → Desktop (create
> shortcut)* for a true one-click desktop launcher.

## How to use (the 5 tabs)

1. **Studios & Fetch** — first click *1) Sync catalogue from Sonar* (discovers
   every project **and its branches**, cached to `data/catalogue.json`). Then
   tick studios and click *2) Fetch selected studios* — it fetches vulns **only
   for the project+branch combos you selected in tab 3**. Watch the live log.
   **Manage studios…** opens a dialog to **add / rename / remove / enable-disable
   studios** — renaming repoints all mapped projects, and the list is saved to
   `data/studios.json` for next time. (OneLink ships disabled — different Sonar
   instance; enable it here when ready.)
2. **Project Mapping** — the editable project→studio table. Select rows, then in
   the box either pick an existing studio **or type a brand-new studio name** and
   click *Assign (new name OK)* — a new studio is created and saved. *Save
   mapping* persists to `data/studio_mapping.csv`. **This is where you fix the
   tricky ones** (e.g. `ati-cxs-Playermax-Administrator` → EX-Mobile).
3. **Scope (Projects & Branches)** — a flat table filtered by **Studio** (top
   right). Each project has a **Branch dropdown** (click the Branch cell to pick
   the branch), an **Include** toggle, and **Critical / High / Medium / Low**
   columns. Click **🔄 Refresh stats** to fetch the vulnerabilities for the chosen
   branches and see them right there (rows with criticals/highs are tinted). One
   branch per project; *Save scope* persists to `data/branch_selection.csv`.
4. **Generate Report** — choose the **Studio** (a single one, or *All studios*),
   the **Period type** (Monthly or Quarterly), the **Current** and **Prior**
   period labels (*Fill from today* suggests them; Monthly → `August'26`,
   Quarterly → `JQ'26`), and the output folder, then click *Generate*. One
   `<Studio>_<label>.xlsx` per studio: Master Sheet / ActiveBranches /
   VulnDetails. VulnDetails shows the **prior-period block auto-filled from
   history** beside the **current-period block** from this run. Every run is
   appended to `data/history.csv` so it becomes next period's "prior"
   automatically. *Backup data now* zips the whole `data\` folder on demand.
5. **Email** — enter To/Cc per studio (saved for next time).
   - **👁 Preview & Edit…** — pick a studio and open an in-app window to review
     and **edit the To/Cc, Subject and message** before anything is sent. Then
     choose **📝 Open draft in Outlook** (edit more and send from Outlook) or
     **✉ Send now**. Optionally tick *Save as my default template* (use
     `{studio}` / `{period}` placeholders) to reuse the wording next time.
   - **Prepare emails for ALL generated studios** — bulk path: opens an Outlook
     **draft** per studio (or sends, if *Bulk send immediately* is ticked),
     using your saved templates. The formatted vulnerability-summary table is
     appended automatically to every mail.

## Severity mapping (as required)

| SonarQube severity | Report bucket |
|--------------------|---------------|
| Blocker            | **Critical**  |
| Critical           | **High**      |
| Major              | **Medium**    |
| Minor + Info       | **Low**       |

Counts come from open (`OPEN,REOPENED`) `VULNERABILITY` issues per project+branch.

## Config

- `app/config.py` — Sonar host, embedded PAT, studio list, severity map,
  colours, active-branch window (90 days), OneLink placeholders.
- `data/studios.json` — the editable studio list (add/rename/remove in the UI).
- `data/studio_mapping.csv` — project→studio table (seeded from All-studios.ods).
- `data/branch_selection.csv` — which project+branch combos to include.
- `data/catalogue.json` — cached projects/branches from the last Sonar sync.
- `data/history.csv` — every generated run (drives the prior-period block).
- `data/settings.json` — remembers output folder, period type/labels, recipients.
- `data/backups/` — **auto-backup zips of the whole `data/` folder every 15
  days** (created on startup when due; also via *Backup data now*). Interval is
  `BACKUP_INTERVAL_DAYS` in `app/config.py`.

## Notes / next steps

- Studio classification is **not** derived from project names (they're
  unreliable) — it's the editable mapping table. Seeded best-effort; review the
  `low`/`Unassigned` rows once.
- OneLink: set `ONELINK_HOST` / `ONELINK_PAT` in `config.py` and remove it from
  `DISABLED_STUDIOS` when ready.
- The prior-quarter (MQ) block fills only once you've generated at least one
  earlier quarter (its data lives in `data/history.csv`). The first ever run has
  a blank prior block — that's expected.

Built on the proven fetch logic from `blazorSonar`.
