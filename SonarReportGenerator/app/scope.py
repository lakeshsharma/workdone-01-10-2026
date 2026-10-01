"""
Report scope + history.

* Catalogue  : cached {project -> key, branches[]} discovered from Sonar.
* BranchSelection : which project+branch combos to include in the report
                    (user-editable; defaults to branches scanned recently).
* History    : every generated run, so the report can auto-fill the
               prior-quarter (MQ) block next to the current quarter (JQ).
"""
from __future__ import annotations

import csv
import datetime as _dt
import json
import os

from . import config


# --------------------------------------------------------------------- catalogue
def load_catalogue() -> dict:
    if os.path.exists(config.CATALOGUE_JSON):
        with open(config.CATALOGUE_JSON, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_catalogue(cat: dict) -> None:
    with open(config.CATALOGUE_JSON, "w", encoding="utf-8") as f:
        json.dump(cat, f, indent=1)


def _is_recent(iso_date: str, days: int) -> bool:
    if not iso_date:
        return False
    try:
        d = _dt.date.fromisoformat(iso_date)
    except ValueError:
        return False
    return (_dt.date.today() - d).days <= days


# --------------------------------------------------------------- branch selection
class BranchSelection:
    """Set of included (project, branch) pairs, persisted to CSV."""

    FIELDS = ["Project_Name", "Branch_Name", "Include"]

    def __init__(self, rows: list[dict]):
        # (project, branch) -> "Yes"/"No"
        self.sel: dict[tuple[str, str], str] = {
            (r["Project_Name"], r["Branch_Name"]): r.get("Include", "Yes") for r in rows
        }

    @classmethod
    def load(cls) -> "BranchSelection":
        rows = []
        if os.path.exists(config.BRANCH_SELECTION_CSV):
            with open(config.BRANCH_SELECTION_CSV, encoding="utf-8") as f:
                rows = list(csv.DictReader(f))
        return cls(rows)

    def save(self) -> None:
        with open(config.BRANCH_SELECTION_CSV, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=self.FIELDS)
            w.writeheader()
            for (proj, br), inc in sorted(self.sel.items()):
                w.writerow({"Project_Name": proj, "Branch_Name": br, "Include": inc})

    def is_included(self, project: str, branch: str) -> bool:
        return str(self.sel.get((project, branch), "No")).strip().lower() in \
            ("yes", "y", "true", "1")

    def set(self, project: str, branch: str, included: bool) -> None:
        self.sel[(project, branch)] = "Yes" if included else "No"

    def set_single(self, project: str, branch: str) -> None:
        """Select exactly ONE branch for a project (used by the Scope dropdown)."""
        for (p, b) in list(self.sel):
            if p == project:
                self.sel[(p, b)] = "No"
        self.sel[(project, branch)] = "Yes"

    def selected_branch(self, project: str, cat: dict | None = None) -> str:
        """The project's chosen branch; if none, default to main / most-recent."""
        inc = self.included_branches(project)
        if inc:
            return inc[0]
        if cat and project in cat:
            branches = cat[project].get("branches", [])
            for b in branches:
                if b.get("isMain"):
                    return b["name"]
            if branches:
                return branches[0]["name"]
        return ""

    def included_branches(self, project: str) -> list[str]:
        return [b for (p, b), inc in self.sel.items()
                if p == project and str(inc).lower() in ("yes", "y", "true", "1")]

    def seed_from_catalogue(self, cat: dict,
                            days: int = config.ACTIVE_BRANCH_DAYS) -> int:
        """
        For any project/branch not yet chosen, default-include branches scanned
        within `days` (fall back to the main branch). Returns count of new rows.
        """
        added = 0
        for project, info in cat.items():
            branches = info.get("branches", [])
            recent = [b["name"] for b in branches if _is_recent(b.get("lastScan", ""), days)]
            if not recent:
                recent = [b["name"] for b in branches if b.get("isMain")]
            for b in branches:
                key = (project, b["name"])
                if key not in self.sel:
                    self.sel[key] = "Yes" if b["name"] in recent else "No"
                    added += 1
        return added


# ------------------------------------------------------------------------ history
class History:
    """Per-run vuln numbers keyed by (quarter, project, branch)."""

    FIELDS = ["Quarter", "Studio", "Project_Name", "Branch",
              "Critical", "High", "Medium", "Low", "Run_date"]

    def __init__(self, rows: list[dict]):
        self.rows = rows

    @classmethod
    def load(cls) -> "History":
        rows = []
        if os.path.exists(config.HISTORY_CSV):
            with open(config.HISTORY_CSV, encoding="utf-8") as f:
                rows = list(csv.DictReader(f))
        return cls(rows)

    def save(self) -> None:
        with open(config.HISTORY_CSV, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=self.FIELDS)
            w.writeheader()
            w.writerows(self.rows)

    def record(self, quarter: str, studio: str, project: str, branch: str,
               c: int, h: int, m: int, low: int) -> None:
        """Insert/replace the row for (quarter, project, branch)."""
        self.rows = [r for r in self.rows
                     if not (r["Quarter"] == quarter
                             and r["Project_Name"] == project
                             and r["Branch"] == branch)]
        self.rows.append({
            "Quarter": quarter, "Studio": studio, "Project_Name": project,
            "Branch": branch, "Critical": c, "High": h, "Medium": m, "Low": low,
            "Run_date": _dt.date.today().isoformat(),
        })

    def prior_for(self, quarter: str, project: str) -> dict | None:
        """
        Best prior-quarter row for a project: prefer the given `quarter` label
        (the user-set prior label); if that project has several branches that
        quarter, pick the one with the highest Critical+High.
        """
        cands = [r for r in self.rows
                 if r["Quarter"] == quarter and r["Project_Name"] == project]
        if not cands:
            return None
        return max(cands, key=lambda r: int(r["Critical"] or 0) + int(r["High"] or 0))

    def quarters(self) -> list[str]:
        return sorted({r["Quarter"] for r in self.rows})
