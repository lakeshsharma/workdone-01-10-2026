"""
Per-studio persistence: the last fetched catalogue (repo/branch/severity
counts) and the user's scope choices (which repo, which branch, include or
not) for report generation.
"""
from __future__ import annotations

import csv
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Optional

from . import config

KEY_SEP = "\x1f"  # unit separator - won't collide with real repo/branch names


def _key(repo: str, branch: str) -> str:
    return f"{repo}{KEY_SEP}{branch}"


def _unkey(key: str) -> tuple[str, str]:
    repo, _, branch = key.partition(KEY_SEP)
    return repo, branch


def save_catalogue(studio: str, branch_counts: dict, total_items: int) -> None:
    config.ensure_dirs()
    payload = {
        "fetched_at": datetime.now().isoformat(timespec="seconds"),
        "total_items": total_items,
        "branch_counts": {
            _key(repo, branch): dict(counts)
            for (repo, branch), counts in branch_counts.items()
        },
    }
    with open(config.catalogue_file(studio), "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def load_catalogue(studio: str) -> Optional[dict]:
    path = config.catalogue_file(studio)
    if not path.exists():
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
    except Exception:
        return None

    branch_counts = {}
    for key, counts in raw.get("branch_counts", {}).items():
        repo, branch = _unkey(key)
        branch_counts[(repo, branch)] = Counter(counts)

    return {
        "fetched_at": raw.get("fetched_at"),
        "total_items": raw.get("total_items", 0),
        "branch_counts": branch_counts,
    }


def build_repo_rows(branch_counts: dict) -> dict[str, list[tuple[str, Counter]]]:
    """Group (repo, branch) -> counts into repo -> [(branch, counts), ...],
    sorted by violation volume descending, excluding the "(No branch)" bucket
    (mirrors the Cycode GUI branch selector, which never lists that either).
    """
    grouped: dict[str, list[tuple[str, Counter]]] = {}
    for (repo, branch), counts in branch_counts.items():
        if branch == "(No branch)":
            continue
        grouped.setdefault(repo, []).append((branch, counts))

    for repo, branches in grouped.items():
        branches.sort(key=lambda b: (-sum(b[1].values()), b[0].lower()))

    return grouped


class ScopeSelection:
    """repo -> (chosen_branch, include)"""

    def __init__(self, studio: str, rows: dict[str, tuple[str, bool]] | None = None):
        self.studio = studio
        self.rows: dict[str, tuple[str, bool]] = rows or {}

    @classmethod
    def load(cls, studio: str) -> "ScopeSelection":
        path = config.scope_file(studio)
        rows: dict[str, tuple[str, bool]] = {}
        if path.exists():
            with open(path, "r", encoding="utf-8", newline="") as f:
                for row in csv.DictReader(f):
                    repo = row.get("repository", "")
                    if not repo:
                        continue
                    branch = row.get("branch", "")
                    include = row.get("include", "1") == "1"
                    rows[repo] = (branch, include)
        return cls(studio, rows)

    def save(self) -> None:
        config.ensure_dirs()
        with open(config.scope_file(self.studio), "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["repository", "branch", "include"])
            for repo, (branch, include) in sorted(self.rows.items(), key=lambda kv: kv[0].lower()):
                writer.writerow([repo, branch, "1" if include else "0"])

    def get(self, repo: str, default_branch: str) -> tuple[str, bool]:
        return self.rows.get(repo, (default_branch, True))

    def set(self, repo: str, branch: str, include: bool) -> None:
        self.rows[repo] = (branch, include)

    def sync_with_repo_rows(self, repo_rows: dict[str, list[tuple[str, Counter]]]) -> None:
        """Add defaults for newly-seen repos; drop repos no longer fetched."""
        for repo, branches in repo_rows.items():
            if repo not in self.rows and branches:
                self.rows[repo] = (branches[0][0], True)
        for repo in list(self.rows):
            if repo not in repo_rows:
                del self.rows[repo]
