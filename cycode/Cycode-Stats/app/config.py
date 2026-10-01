"""
Paths, defaults and small persisted-settings helpers for Cycode-Stats.

Studios map to a Cycode "project id" (the id used in the Cycode dashboard
URL / `--project-ids` flag). Within one project id, Cycode returns many
repositories, each with one or more branches.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

APP_NAME = "Cycode-Stats"


def _base_dir() -> Path:
    if getattr(sys, "frozen", False):
        # Running as a PyInstaller-built exe: keep data next to the exe so
        # it's writable and survives upgrades.
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


BASE_DIR = _base_dir()
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "output"

STUDIOS_FILE = DATA_DIR / "studios.json"
SETTINGS_FILE = DATA_DIR / "settings.json"


def scope_file(studio: str) -> Path:
    return DATA_DIR / f"scope_{_safe(studio)}.csv"


def catalogue_file(studio: str) -> Path:
    return DATA_DIR / f"catalogue_{_safe(studio)}.json"


def _safe(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in name)


# Seeded from what's confirmed today; more studios can be added in-app via
# "Manage Studios" without touching code.
DEFAULT_STUDIOS = {
    "OneLink": 36416,
    "System7000": 25214,
}

STATUS = "Open"
PAGE_SIZE = 1000
SEVERITIES = ("Critical", "High", "Medium", "Low", "Info")

# Cycode can return historical/legacy repository names in violation records
# even when the GUI shows only the current repository name. Normalize those
# aliases so the Excel matches the GUI repository selector and totals.
REPOSITORY_ALIASES = {
    "s7k-build-pipelines": "cxs-s7k-build-pipelines",
}


def ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def load_studios() -> dict[str, int]:
    ensure_dirs()
    if not STUDIOS_FILE.exists():
        save_studios(DEFAULT_STUDIOS)
        return dict(DEFAULT_STUDIOS)
    try:
        with open(STUDIOS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return {str(k): int(v) for k, v in data.items()}
    except Exception:
        return dict(DEFAULT_STUDIOS)


def save_studios(studios: dict[str, int]) -> None:
    ensure_dirs()
    with open(STUDIOS_FILE, "w", encoding="utf-8") as f:
        json.dump(studios, f, indent=2, sort_keys=True)


def load_settings() -> dict:
    ensure_dirs()
    if not SETTINGS_FILE.exists():
        return {}
    try:
        with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_settings(settings: dict) -> None:
    ensure_dirs()
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, sort_keys=True)
