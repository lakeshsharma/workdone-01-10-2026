"""
Central configuration for the SonarQube Vulnerability Reporter.

Everything a normal user might want to change lives here or in the
CSV/JSON files under the data/ folder. The PAT is embedded so the packaged
.exe runs with a single click (no external setup).
"""
import os
import sys

# ---------------------------------------------------------------------------
# App identity — window title / header / footer / email signature.
# The CI build workflow overwrites these two lines for a given build; keep
# them on their own line in this exact form so the substitution stays simple.
# ---------------------------------------------------------------------------
APP_NAME = "SonarQube Vulnerability Reporter"
APP_VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# Paths (work both when run as a .py and when frozen into a PyInstaller .exe)
# ---------------------------------------------------------------------------
def _base_dir() -> str:
    if getattr(sys, "frozen", False):          # running as bundled .exe
        return os.path.dirname(sys.executable)
    # running as source: project root is one level up from /app
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BASE_DIR = _base_dir()
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)


def ensure_seed_data() -> None:
    """When running as a bundled .exe, copy any seed files that ship inside the
    bundle into the writable data/ folder next to the exe (first run only)."""
    if not getattr(sys, "frozen", False):
        return
    import shutil
    bundled = os.path.join(getattr(sys, "_MEIPASS", ""), "data")
    if not os.path.isdir(bundled):
        return
    for fn in os.listdir(bundled):
        dst = os.path.join(DATA_DIR, fn)
        if not os.path.exists(dst):
            try:
                shutil.copy2(os.path.join(bundled, fn), dst)
            except Exception:  # noqa: BLE001
                pass

STUDIO_MAPPING_CSV = os.path.join(DATA_DIR, "studio_mapping.csv")
BRANCH_SELECTION_CSV = os.path.join(DATA_DIR, "branch_selection.csv")
CATALOGUE_JSON = os.path.join(DATA_DIR, "catalogue.json")
HISTORY_CSV = os.path.join(DATA_DIR, "history.csv")
SETTINGS_JSON = os.path.join(DATA_DIR, "settings.json")
STUDIOS_JSON = os.path.join(DATA_DIR, "studios.json")
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
DEFAULT_OUTPUT_DIR = os.path.join(BASE_DIR, "output")

# Auto-backup the data/ folder this often (days).
BACKUP_INTERVAL_DAYS = 15

# ---------------------------------------------------------------------------
# SonarQube connection
# ---------------------------------------------------------------------------
# Primary (production) SonarQube host used by the 6 active studios.
SONAR_HOST = "quality.aristocrat.com"

# Embedded Personal Access Token (base64, as stored in blazorSonar/config/pat_config.txt).
# The Authorization header is "Basic <token>". Trailing ':' is part of the base64 encoding.
SONAR_PAT = "c3F1XzI4NWVmYjU2NjJiNjc3ZDRhZDc3NTdjM2Q0YmEzOTAxODAyNzc1NjY6"

# OneLink lives on a DIFFERENT SonarQube instance. Not fetched yet, wired for the future.
ONELINK_HOST = ""          # e.g. "quality-onelink.aristocrat.com"
ONELINK_PAT = ""

# ---------------------------------------------------------------------------
# Studios  (defaults only — the live, EDITABLE list lives in data/studios.json)
# ---------------------------------------------------------------------------
# OneLink is listed but disabled (different Sonar instance, ignored for now).
DEFAULT_STUDIOS = ["nCompass", "CX-Mobile", "EX-Mobile", "Oasis", "Loyalty", "System7000", "OneLink"]
DEFAULT_DISABLED = ["OneLink"]          # shown in UI but not fetched yet
UNASSIGNED = "Unassigned"               # bucket for projects not yet mapped to a studio

# Backwards-compatible alias (some helpers import config.STUDIOS as a default).
STUDIOS = DEFAULT_STUDIOS


def load_studios() -> dict:
    """Return {'studios': [...], 'disabled': [...]} from data/studios.json,
    seeding the file from defaults on first run."""
    import json
    if os.path.exists(STUDIOS_JSON):
        try:
            with open(STUDIOS_JSON, encoding="utf-8") as f:
                d = json.load(f)
                return {"studios": d.get("studios", list(DEFAULT_STUDIOS)),
                        "disabled": d.get("disabled", list(DEFAULT_DISABLED))}
        except Exception:  # noqa: BLE001
            pass
    d = {"studios": list(DEFAULT_STUDIOS), "disabled": list(DEFAULT_DISABLED)}
    save_studios(d)
    return d


def save_studios(d: dict) -> None:
    import json
    with open(STUDIOS_JSON, "w", encoding="utf-8") as f:
        json.dump({"studios": d.get("studios", []),
                   "disabled": d.get("disabled", [])}, f, indent=2)

# ---------------------------------------------------------------------------
# Severity mapping  (Sonar classic severity  ->  report bucket)
#   Blocker -> Critical | Critical -> High | Major -> Medium | Minor+Info -> Low
# ---------------------------------------------------------------------------
SEVERITY_MAP = {
    "BLOCKER": "Critical",
    "CRITICAL": "High",
    "MAJOR": "Medium",
    "MINOR": "Low",
    "INFO": "Low",
}
BUCKETS = ["Critical", "High", "Medium", "Low"]

# A branch counts as "active" if it was scanned within this many days.
ACTIVE_BRANCH_DAYS = 90

# ---------------------------------------------------------------------------
# Report look & feel (hex colours chosen to match the template workbook)
# ---------------------------------------------------------------------------
COLOR_HEADER = "DDEBF7"      # light blue  (template header fill)
COLOR_TOTAL = "BDD7EE"       # slightly darker blue for totals row
COLOR_YELLOW = "FFFF00"      # "needs verification" highlight
COLOR_GREEN = "C6E0B4"       # ok / verified
COLOR_CRIT = "FFC7CE"        # light red for non-zero critical/high cells

QUARTER_LABEL = ""           # e.g. "JQ'26"; if blank the UI computes one from today's date

# ---------------------------------------------------------------------------
# Reporting period — the tool works for MONTHLY or QUARTERLY cycles.
# The label is what shows on the VulnDetails banners, sheet names and filename.
#   Quarterly -> Aristocrat style: MQ'26 / JQ'26 / SQ'26 / DQ'26
#   Monthly   -> month name:       January'26, February'26, ...
# ---------------------------------------------------------------------------
PERIOD_TYPES = ["Monthly", "Quarterly"]

_MONTHS = ["January", "February", "March", "April", "May", "June",
           "July", "August", "September", "October", "November", "December"]
# Aristocrat fiscal-quarter letters keyed by calendar quarter (editable if wrong).
_QUARTER_LETTER = {1: "MQ", 2: "JQ", 3: "SQ", 4: "DQ"}


def default_period_label(period_type: str, when=None) -> str:
    import datetime as _dt
    d = when or _dt.date.today()
    yy = str(d.year)[2:]
    if period_type == "Monthly":
        return f"{_MONTHS[d.month - 1]}'{yy}"
    q = (d.month - 1) // 3 + 1
    return f"{_QUARTER_LETTER[q]}'{yy}"


def previous_period_label(period_type: str, when=None) -> str:
    import datetime as _dt
    d = when or _dt.date.today()
    if period_type == "Monthly":
        first = d.replace(day=1)
        prev = first - _dt.timedelta(days=1)
        return default_period_label("Monthly", prev)
    # go back ~3 months for the previous quarter
    m = d.month - 3
    y = d.year
    if m <= 0:
        m += 12
        y -= 1
    return default_period_label("Quarterly", _dt.date(y, m, 1))
