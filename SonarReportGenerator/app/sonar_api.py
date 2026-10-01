"""
Thin SonarQube REST client + fetch helpers.

Reuses the exact endpoints/logic proven in blazorSonar, but:
  * uses `requests` (with a session + retries),
  * maps severities into the 4 report buckets (Critical/High/Medium/Low),
  * reports progress via an optional callback so the GUI stays responsive.
"""
from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass, field

import requests

from . import config


@dataclass
class BranchVuln:
    branch: str
    is_main: bool
    quality_gate: str
    last_scan: _dt.date | None
    critical: int = 0
    high: int = 0
    medium: int = 0
    low: int = 0

    @property
    def total_ch(self) -> int:
        return self.critical + self.high

    @property
    def active(self) -> bool:
        if not self.last_scan:
            return False
        return (_dt.date.today() - self.last_scan).days <= config.ACTIVE_BRANCH_DAYS


@dataclass
class ProjectVuln:
    key: str
    name: str
    studio: str = ""
    branches: list[BranchVuln] = field(default_factory=list)

    @property
    def dashboard_url(self) -> str:
        return f"https://{config.SONAR_HOST}/dashboard?id={self.key}"

    def active_branches(self) -> list[BranchVuln]:
        act = [b for b in self.branches if b.active]
        return act or [b for b in self.branches if b.is_main] or self.branches[:1]


class SonarClient:
    def __init__(self, host: str = config.SONAR_HOST, pat: str = config.SONAR_PAT):
        self.base = f"https://{host}"
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Basic {pat}"})

    def _get(self, path: str, params: dict | None = None) -> dict:
        r = self.session.get(self.base + path, params=params or {}, timeout=60)
        r.raise_for_status()
        return r.json()

    # -- catalogue -------------------------------------------------------
    def list_projects(self) -> list[dict]:
        out, page = [], 1
        while True:
            data = self._get("/api/components/search_projects",
                             {"ps": 500, "p": page})
            comps = data.get("components", [])
            out.extend(comps)
            paging = data.get("paging", {})
            if page * paging.get("pageSize", 500) >= paging.get("total", len(out)):
                break
            page += 1
            if page > 20:
                break
        return out

    def list_branches(self, project_key: str) -> list[dict]:
        try:
            return self._get("/api/project_branches/list",
                             {"project": project_key}).get("branches", [])
        except requests.HTTPError:
            return []

    def severity_counts(self, project_key: str, branch: str) -> dict[str, int]:
        """Return {Critical,High,Medium,Low} for open VULNERABILITY issues."""
        buckets = {b: 0 for b in config.BUCKETS}
        data = self._get("/api/issues/search", {
            "componentKeys": project_key,
            "branch": branch,
            "types": "VULNERABILITY",
            "statuses": "OPEN,REOPENED",
            "facets": "severities",
            "ps": 1,
        })
        for facet in data.get("facets", []):
            if facet.get("property") == "severities":
                for v in facet.get("values", []):
                    bucket = config.SEVERITY_MAP.get(v["val"])
                    if bucket:
                        buckets[bucket] += int(v["count"])
        return buckets


def build_catalogue(client: "SonarClient", progress_cb=None) -> dict:
    """
    Discover every project and its branches (names + last-scan date + isMain).
    Returns {project_name: {"key":.., "branches":[{"name","isMain","lastScan"}]}}.
    `progress_cb(done, total, name)` is called as it goes (optional).
    """
    projects = client.list_projects()
    total = len(projects)
    cat: dict = {}
    for i, p in enumerate(projects, 1):
        key, name = p["key"], p["name"]
        branches = []
        for br in client.list_branches(key):
            d = _parse_date(br.get("analysisDate"))
            branches.append({
                "name": br["name"],
                "isMain": br.get("isMain", False),
                "lastScan": d.isoformat() if d else "",
            })
        cat[name] = {"key": key, "branches": branches}
        if progress_cb:
            progress_cb(i, total, name)
    return cat


def _parse_date(s: str | None) -> _dt.date | None:
    if not s:
        return None
    try:
        return _dt.datetime.fromisoformat(s.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def fetch_project(client: SonarClient, key: str, name: str,
                  active_only: bool = True) -> ProjectVuln:
    """Fetch every (active) branch of one project with its vuln buckets."""
    proj = ProjectVuln(key=key, name=name)
    for br in client.list_branches(key):
        bv = BranchVuln(
            branch=br["name"],
            is_main=br.get("isMain", False),
            quality_gate=br.get("status", {}).get("qualityGateStatus", "NONE"),
            last_scan=_parse_date(br.get("analysisDate")),
        )
        proj.branches.append(bv)

    branches = proj.active_branches() if active_only else proj.branches
    for bv in branches:
        counts = client.severity_counts(key, bv.branch)
        bv.critical, bv.high = counts["Critical"], counts["High"]
        bv.medium, bv.low = counts["Medium"], counts["Low"]
    # keep only the branches we actually costed if active_only
    if active_only:
        proj.branches = branches
    return proj
