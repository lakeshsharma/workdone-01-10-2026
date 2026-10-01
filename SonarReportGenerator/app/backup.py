"""
Automatic backup of the data/ folder.

On startup the app calls maybe_backup(): if the last backup is older than
BACKUP_INTERVAL_DAYS (15), it zips all data files into data/backups/.
A manual "Backup now" button calls run_backup() directly.
"""
from __future__ import annotations

import datetime as _dt
import glob
import os
import zipfile

from . import config


def _last_backup_date() -> _dt.date | None:
    dates = []
    for p in glob.glob(os.path.join(config.BACKUP_DIR, "data_backup_*.zip")):
        stem = os.path.basename(p)[len("data_backup_"):-len(".zip")]
        try:
            dates.append(_dt.date.fromisoformat(stem[:10]))
        except ValueError:
            continue
    return max(dates) if dates else None


def run_backup() -> str:
    """Create a zip of all data files (excluding the backups folder). Returns path."""
    os.makedirs(config.BACKUP_DIR, exist_ok=True)
    stamp = _dt.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    path = os.path.join(config.BACKUP_DIR, f"data_backup_{stamp}.zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for fn in os.listdir(config.DATA_DIR):
            full = os.path.join(config.DATA_DIR, fn)
            if os.path.isfile(full):
                zf.write(full, arcname=fn)
    return path


def maybe_backup() -> str | None:
    """Back up only if due (>= interval since the last one). Returns path or None."""
    last = _last_backup_date()
    due = (last is None or
           (_dt.date.today() - last).days >= config.BACKUP_INTERVAL_DAYS)
    if not due:
        return None
    try:
        return run_backup()
    except Exception:  # noqa: BLE001
        return None
