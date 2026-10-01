"""
Project -> Studio mapping.

The mapping is deliberately data-driven and user-editable because Sonar project
names do NOT reliably encode the studio (e.g. `ati-cxs-Playermax-Administrator`
is EX-Mobile even though the ODS labels it CX-Mobile). The GUI edits this table;
this module just loads/saves it and offers a best-effort auto-guess for projects
that appear in Sonar but not yet in the mapping file.
"""
from __future__ import annotations

import csv
import os

from . import config

FIELDS = ["Project_Name", "Studio", "Include", "Confidence", "Source"]

# Keyword rules used to *guess* a studio for brand-new projects only.
# Order matters: first match wins. Lower-cased substring match on the key.
_KEYWORD_RULES = [
    ("ncompass", "nCompass"),
    ("playermax", "EX-Mobile"),
    ("playeractivity", "EX-Mobile"),
    ("selfexclusion", "EX-Mobile"),
    ("ex-mobile", "EX-Mobile"),
    ("applesse", "CX-Mobile"),
    ("mobilefoundation", "CX-Mobile"),
    ("mobility", "CX-Mobile"),
    ("cx-mobile", "CX-Mobile"),
    ("loyalty", "Loyalty"),
    ("s7000", "System7000"),
    ("system7000", "System7000"),
    ("onelink", "OneLink"),
    ("oasis", "Oasis"),
    ("floor", "Oasis"),
    ("gaming.wallet", "Oasis"),
    ("gpms", "Oasis"),
    ("ordering", "Oasis"),
    ("dynamic", "Oasis"),
]


def guess_studio(project_name: str) -> str:
    low = project_name.lower()
    for kw, studio in _KEYWORD_RULES:
        if kw in low:
            return studio
    return config.UNASSIGNED


class StudioMap:
    def __init__(self, rows: list[dict]):
        # keyed by project name
        self.rows: dict[str, dict] = {r["Project_Name"]: r for r in rows}

    # -- persistence -----------------------------------------------------
    @classmethod
    def load(cls) -> "StudioMap":
        rows = []
        if os.path.exists(config.STUDIO_MAPPING_CSV):
            with open(config.STUDIO_MAPPING_CSV, encoding="utf-8") as f:
                for r in csv.DictReader(f):
                    rows.append({k: r.get(k, "") for k in FIELDS})
        return cls(rows)

    def save(self) -> None:
        with open(config.STUDIO_MAPPING_CSV, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS)
            w.writeheader()
            for name in sorted(self.rows):
                w.writerow(self.rows[name])

    # -- queries ---------------------------------------------------------
    def studio_of(self, project_name: str) -> str:
        r = self.rows.get(project_name)
        return r["Studio"] if r else config.UNASSIGNED

    def included(self, project_name: str) -> bool:
        r = self.rows.get(project_name)
        return not r or str(r.get("Include", "Yes")).strip().lower() in ("yes", "y", "true", "1")

    def projects_for(self, studio: str) -> list[str]:
        return sorted(
            name for name, r in self.rows.items()
            if r["Studio"] == studio and self.included(name)
        )

    def studio_counts(self, studios: list[str] | None = None) -> dict[str, int]:
        base = list(studios) if studios else list(config.DEFAULT_STUDIOS)
        out = {s: 0 for s in base + [config.UNASSIGNED]}
        for r in self.rows.values():
            out[r["Studio"]] = out.get(r["Studio"], 0) + 1
        return out

    def rename_studio(self, old: str, new: str) -> int:
        """Repoint every project mapped to `old` onto `new`. Returns count."""
        n = 0
        for r in self.rows.values():
            if r["Studio"] == old:
                r["Studio"] = new
                n += 1
        return n

    # -- reconciliation with live Sonar catalogue -----------------------
    def sync_with_catalogue(self, project_keys_names: list[tuple[str, str]]) -> list[str]:
        """
        Add any Sonar projects not yet in the mapping, guessing their studio.
        Returns the list of newly-added project names (so the UI can flag them).
        """
        added = []
        for _key, name in project_keys_names:
            if name not in self.rows:
                self.rows[name] = {
                    "Project_Name": name,
                    "Studio": guess_studio(name),
                    "Include": "Yes",
                    "Confidence": "low",
                    "Source": "auto-new",
                }
                added.append(name)
        return added
