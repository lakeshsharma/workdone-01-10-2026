"""Entry point for Cycode-Stats."""
import io
import sys
import traceback

# A --windowed/--noconsole PyInstaller build has no console, so sys.stdout
# and sys.stderr are None. cycode's own logger module unconditionally calls
# sys.stdout.reconfigure(...) at import time, which crashes with
# "'NoneType' object has no attribute 'reconfigure'" unless we give it real
# (if discarded) text streams first. Must run before any other import.
if sys.stdout is None:
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
if sys.stderr is None:
    sys.stderr = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")


def main():
    from app import config
    config.ensure_dirs()
    from app.gui import run
    run()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Last-resort surface for the frozen exe (no console attached).
        try:
            import tkinter as tk
            from tkinter import messagebox
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Cycode-Stats - Fatal error", traceback.format_exc())
        except Exception:
            traceback.print_exc()
        sys.exit(1)
