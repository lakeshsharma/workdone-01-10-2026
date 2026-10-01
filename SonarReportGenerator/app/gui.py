"""
Tkinter desktop UI (styled).

Tabs: 1 Studios & Fetch | 2 Project Mapping | 3 Scope (Projects & Branches)
      | 4 Generate Report | 5 Email | 6 Custom Sort | 7 Dashboard
"""
from __future__ import annotations

import json
import os
import queue
import threading

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

from . import backup, config, mailer, report, scope
from .sonar_api import SonarClient, build_catalogue
from .studios import StudioMap

CHECK = "☑"
UNCHECK = "☐"

# ---- palette --------------------------------------------------------------
# Same indigo/teal/gold "tech dashboard" identity, toned down for a subtler feel.
PRIMARY = "#6366F1"       # muted indigo
PRIMARY_DK = "#4F46E5"    # pressed/hover indigo
PRIMARY_LT = "#A5B4FC"    # soft lilac (header gradient end)
ACCENT = "#14B8A6"        # muted teal
ACCENT_DK = "#0D9488"
GOLD = "#D97706"          # muted amber accent (progress bar, thin underline)
BG = "#F7F7FB"            # near-white, faint lavender app background
CARD = "#FFFFFF"
TEXT = "#2B2A3D"          # soft dark indigo-grey text
MUTED = "#807C93"         # muted slate-violet
STRIPE = "#F1F1F8"        # faint row stripe
CRIT_BG = "#FBE2E4"       # muted rose
HIGH_BG = "#FBEEDC"       # muted peach
MED_BG = "#FBF3D9"        # muted pale gold
LOW_BG = "#E2F3EC"        # muted pale teal
UNSCANNED_BG = "#EAEAF2"  # soft grey-lavender
BORDER = "#E4E3EE"        # subtle card/section border
TOOLBAR_BG = "#F0F0F8"    # search/toolbar strip background
ON_PRIMARY = "#E7E6FB"    # muted text sitting on the primary banner
CONSOLE_BG = "#221F30"    # soft dark console background
CONSOLE_FG = "#C4C0D8"    # light lavender console text
DISABLED_BG = "#E3E1ED"   # disabled control fill

# severity chart colors (distinct hues, still muted)
SEV_CRITICAL = "#D9636F"
SEV_HIGH = "#E1974F"
SEV_MEDIUM = "#D9B23C"
SEV_LOW = "#4FAE93"
SEV_COLORS = {"Critical": SEV_CRITICAL, "High": SEV_HIGH,
              "Medium": SEV_MEDIUM, "Low": SEV_LOW}


class RoundButton(tk.Canvas):
    """A pill-shaped button (drop-in look for ttk.Button) with real rounded corners."""

    KINDS = {
        "accent": {"fill": PRIMARY, "hover": PRIMARY_DK, "fg": "white",
                   "outline": None, "pad": (18, 10)},
        "teal":   {"fill": ACCENT, "hover": ACCENT_DK, "fg": "white",
                   "outline": None, "pad": (18, 10)},
        "plain":  {"fill": CARD, "hover": STRIPE, "fg": TEXT,
                   "outline": BORDER, "pad": (14, 8)},
    }

    def __init__(self, parent, text, command=None, kind="plain", bg=BG,
                 font=("Segoe UI Semibold", 10), padx=None, pady=None):
        spec = self.KINDS.get(kind, self.KINDS["plain"])
        self.fill = spec["fill"]
        self.hover_fill = spec["hover"]
        self.fg = spec["fg"]
        self.outline = spec["outline"]
        self.command = command
        self.font = font
        self._text = text
        self._enabled = True
        self._hover = False

        px, py = spec["pad"]
        px = padx if padx is not None else px
        py = pady if pady is not None else py

        probe = tk.Label(parent, text=text, font=font)
        probe.update_idletasks()
        self._bw = probe.winfo_reqwidth() + px * 2
        self._bh = probe.winfo_reqheight() + py * 2
        probe.destroy()
        self._radius = self._bh // 2

        super().__init__(parent, width=self._bw, height=self._bh,
                         highlightthickness=0, bd=0, bg=bg, cursor="hand2")
        self._draw(self.fill)
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)

    def _points(self):
        r, w, h = self._radius, self._bw, self._bh
        x1, y1, x2, y2 = 0, 0, w, h
        return [
            x1 + r, y1, x1 + r, y1, x2 - r, y1, x2 - r, y1,
            x2, y1, x2, y1 + r, x2, y1 + r, x2, y2 - r,
            x2, y2 - r, x2, y2, x2 - r, y2, x2 - r, y2,
            x1 + r, y2, x1 + r, y2, x1, y2, x1, y2 - r,
            x1, y2 - r, x1, y1 + r, x1, y1 + r, x1, y1,
        ]

    def _draw(self, fill):
        self.delete("all")
        outline = self.outline or fill
        self.create_polygon(self._points(), smooth=True, splinesteps=24,
                            fill=fill, outline=outline)
        fg = self.fg if self._enabled else MUTED
        self.create_text(self._bw / 2, self._bh / 2, text=self._text,
                         fill=fg, font=self.font)

    def _on_enter(self, _e=None):
        self._hover = True
        if self._enabled:
            self._draw(self.hover_fill)

    def _on_leave(self, _e=None):
        self._hover = False
        if self._enabled:
            self._draw(self.fill)

    def _on_press(self, _e=None):
        if self._enabled:
            self._draw(self.hover_fill)

    def _on_release(self, _e=None):
        if not self._enabled:
            return
        fire = self._hover
        self._draw(self.hover_fill if self._hover else self.fill)
        if fire and self.command:
            self.command()

    def configure(self, **kw):
        if "state" in kw:
            state = kw.pop("state")
            self._enabled = state != "disabled"
            self._draw(self.fill if self._enabled else DISABLED_BG)
        if kw:
            super().configure(**kw)

    config = configure

    def set_selected(self, selected: bool):
        """Recolor this pill as the active ('accent') or inactive ('plain') tab."""
        spec = self.KINDS["accent"] if selected else self.KINDS["plain"]
        self.fill, self.hover_fill = spec["fill"], spec["hover"]
        self.fg, self.outline = spec["fg"], spec["outline"]
        self._draw(self.hover_fill if self._hover else self.fill)


class RoundTabs(tk.Frame):
    """A ttk.Notebook drop-in — pill-shaped tab buttons switching stacked frames."""

    def __init__(self, parent, bg=BG):
        super().__init__(parent, bg=bg)
        self._bar = tk.Frame(self, bg=bg)
        self._bar.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(0, weight=1)
        self._tabs: list[tuple[RoundButton, tk.Widget]] = []

    def add(self, child, text=""):
        child.grid(row=1, column=0, sticky="nsew")
        btn = RoundButton(self._bar, text=text, kind="plain", bg=self["bg"],
                          command=lambda c=child: self._select(c))
        btn.pack(side="left", padx=(0, 6), pady=2)
        self._tabs.append((btn, child))
        if len(self._tabs) == 1:
            self._select(child)
        else:
            child.lower()
        return child

    def _select(self, child):
        for btn, c in self._tabs:
            btn.set_selected(c is child)
        child.tkraise()


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(config.APP_NAME)
        self.geometry("1120x740")
        self.configure(bg=BG)

        sd = config.load_studios()
        self.studios: list[str] = sd["studios"]
        self.disabled: set[str] = set(sd["disabled"])

        self.smap = StudioMap.load()
        self.bsel = scope.BranchSelection.load()
        self.cat = scope.load_catalogue()
        self.history = scope.History.load()
        self.settings = self._load_settings()

        self.results: dict[str, list[dict]] = {}
        self.scope_cache: dict[str, dict] = {}   # project -> {branch,c,h,m,l}
        self.generated: dict[str, str] = {}
        self.log_q: queue.Queue[str] = queue.Queue()
        self.studio_vars: dict[str, tk.BooleanVar] = {}
        self._branch_editor = None

        self.minsize(1000, 640)
        self._apply_style()
        self._build_header()
        self._build_footer()

        self.nb = RoundTabs(self)
        self.nb.pack(fill="both", expand=True, padx=10, pady=(0, 6))
        self._build_fetch_tab(self.nb)
        self._build_mapping_tab(self.nb)
        self._build_scope_tab(self.nb)
        self._build_generate_tab(self.nb)
        self._build_email_tab(self.nb)
        self._build_sort_tab(self.nb)
        self._build_dashboard_tab(self.nb)

        self._update_footer()
        self.after(150, self._drain_log)
        self._startup_backup()

    def _build_footer(self):
        bar = tk.Frame(self, bg=PRIMARY_DK)
        bar.pack(side="bottom", fill="x")
        self.footer = tk.Label(bar, text="", bg=PRIMARY_DK, fg=ON_PRIMARY,
                               font=("Segoe UI", 8), anchor="w", padx=12, pady=4)
        self.footer.pack(side="left")

    def _update_footer(self):
        if hasattr(self, "footer"):
            self.footer.configure(
                text=f"📁 Data: {config.DATA_DIR}    •    "
                     f"{len(self.cat)} projects in catalogue    •    "
                     f"{len(self.smap.rows)} mapped    •    "
                     f"{len(self.studios)} studios    •    "
                     f"v{config.APP_VERSION}")

    # ------------------------------------------------------------ styling
    def _apply_style(self):
        st = ttk.Style(self)
        try:
            st.theme_use("clam")
        except tk.TclError:
            pass
        base = ("Segoe UI", 10)
        st.configure(".", background=BG, foreground=TEXT, font=base)
        st.configure("TFrame", background=BG)
        st.configure("Card.TFrame", background=CARD)
        st.configure("TLabel", background=BG, foreground=TEXT, font=base)
        st.configure("Card.TLabel", background=CARD, foreground=TEXT, font=base)
        st.configure("Muted.TLabel", background=BG, foreground=MUTED, font=("Segoe UI", 9))
        st.configure("H1.TLabel", background=PRIMARY, foreground="white",
                     font=("Segoe UI Semibold", 15))
        st.configure("Sub.TLabel", background=PRIMARY, foreground=ON_PRIMARY,
                     font=("Segoe UI", 9))
        st.configure("Section.TLabel", background=BG, foreground=PRIMARY,
                     font=("Segoe UI Semibold", 11))
        st.configure("TCheckbutton", background=BG, font=base)
        st.map("TCheckbutton", background=[("active", BG)])
        try:
            st.map("TCheckbutton", indicatorcolor=[("selected", ACCENT), ("!selected", CARD)])
        except tk.TclError:
            pass

        st.configure("TButton", font=base, padding=(10, 6))
        st.configure("Accent.TButton", background=PRIMARY, foreground="white",
                     padding=(14, 8), font=("Segoe UI Semibold", 10), borderwidth=0,
                     focuscolor=PRIMARY)
        st.map("Accent.TButton",
               background=[("active", PRIMARY_DK), ("pressed", PRIMARY_DK),
                           ("disabled", "#C9C0F5")])
        st.configure("Teal.TButton", background=ACCENT, foreground="white",
                     padding=(14, 8), font=("Segoe UI Semibold", 10), borderwidth=0,
                     focuscolor=ACCENT)
        st.map("Teal.TButton",
               background=[("active", ACCENT_DK), ("pressed", ACCENT_DK)])

        st.configure("TNotebook", background=BG, borderwidth=0, tabmargins=(10, 10, 10, 0))
        st.configure("TNotebook.Tab", padding=(18, 10), font=("Segoe UI Semibold", 10),
                     borderwidth=0)
        st.map("TNotebook.Tab",
               background=[("selected", PRIMARY), ("!selected", TOOLBAR_BG)],
               foreground=[("selected", "white"), ("!selected", MUTED)],
               expand=[("selected", (2, 2, 2, 0))])

        st.configure("Treeview", rowheight=28, fieldbackground=CARD,
                     background=CARD, foreground=TEXT, font=("Segoe UI", 9),
                     borderwidth=0)
        st.configure("Treeview.Heading", font=("Segoe UI Semibold", 9),
                     background=PRIMARY, foreground="white", padding=6, relief="flat")
        st.map("Treeview.Heading", background=[("active", PRIMARY_DK)])
        st.map("Treeview", background=[("selected", ACCENT)],
               foreground=[("selected", "white")])
        st.configure("TCombobox", padding=4, fieldbackground=CARD, arrowsize=13)
        st.configure("Horizontal.TProgressbar", background=GOLD,
                     troughcolor=STRIPE, thickness=12, borderwidth=0)
        st.configure("Toolbar.TFrame", background=TOOLBAR_BG)
        st.configure("Toolbar.TLabel", background=TOOLBAR_BG, foreground=MUTED,
                     font=("Segoe UI", 9))
        st.configure("Count.TLabel", background=TOOLBAR_BG, foreground=PRIMARY,
                     font=("Segoe UI Semibold", 9))
        st.configure("Search.TEntry", padding=6, fieldbackground="white")

    def _build_header(self):
        h = tk.Canvas(self, height=70, highlightthickness=0, bd=0, bg=PRIMARY)
        h.pack(fill="x")
        self._header_canvas = h
        h.bind("<Configure>", self._draw_header)

    @staticmethod
    def _blend(c1: str, c2: str, t: float) -> str:
        r1, g1, b1 = int(c1[1:3], 16), int(c1[3:5], 16), int(c1[5:7], 16)
        r2, g2, b2 = int(c2[1:3], 16), int(c2[3:5], 16), int(c2[5:7], 16)
        r, g, b = (int(r1 + (r2 - r1) * t), int(g1 + (g2 - g1) * t), int(b1 + (b2 - b1) * t))
        return f"#{r:02x}{g:02x}{b:02x}"

    def _draw_header(self, event=None):
        c = self._header_canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w <= 1:
            return
        steps = max(w // 6, 1)
        for i in range(steps):
            t = i / max(steps - 1, 1)
            color = self._blend(PRIMARY, PRIMARY_LT, t)
            x0 = int(i * w / steps)
            x1 = int((i + 1) * w / steps) + 1
            c.create_rectangle(x0, 0, x1, h, outline="", fill=color)
        c.create_rectangle(0, h - 3, w, h, outline="", fill=GOLD)
        title = c.create_text(20, h / 2, anchor="w",
                              text=f"🛡  {config.APP_NAME}",
                              fill="white", font=("Segoe UI Semibold", 16))
        x2 = c.bbox(title)[2] + 16
        c.create_text(x2, h / 2, anchor="w",
                      text="Aristocrat · studios → vulnerabilities → Excel → Outlook",
                      fill=ON_PRIMARY, font=("Segoe UI", 9))

    # ------------------------------------------------------------ misc
    def _studio_choices(self) -> list[str]:
        return list(self.studios) + [config.UNASSIGNED]

    def _startup_backup(self):
        path = backup.maybe_backup()
        if path:
            self.log(f"Auto-backup created (every {config.BACKUP_INTERVAL_DAYS} days): "
                     f"{os.path.basename(path)}")

    def _load_settings(self) -> dict:
        if os.path.exists(config.SETTINGS_JSON):
            try:
                with open(config.SETTINGS_JSON, encoding="utf-8") as f:
                    return json.load(f)
            except Exception:  # noqa: BLE001
                pass
        return {"output_dir": config.DEFAULT_OUTPUT_DIR, "period_type": "Monthly",
                "period_label": "", "prior_label": "", "recipients": {},
                "send_directly": False}

    def _save_settings(self):
        with open(config.SETTINGS_JSON, "w", encoding="utf-8") as f:
            json.dump(self.settings, f, indent=2)

    def log(self, msg: str):
        self.log_q.put(msg)

    def _drain_log(self):
        try:
            while True:
                msg = self.log_q.get_nowait()
                self.log_box.configure(state="normal")
                self.log_box.insert("end", msg + "\n")
                self.log_box.see("end")
                self.log_box.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(150, self._drain_log)

    # ============================================================ TAB 1: Fetch
    def _build_fetch_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="1. Studios & Fetch")

        head = ttk.Frame(f)
        head.pack(fill="x")
        ttk.Label(head, text="Discover projects/branches, then fetch vulnerabilities",
                  style="Section.TLabel").pack(side="left")
        RoundButton(head, text="⚙  Manage studios", kind="accent",
                   command=self._open_studio_manager).pack(side="right")

        self.studio_check_frame = ttk.Frame(f)
        self.studio_check_frame.pack(anchor="w", pady=(8, 4))
        self._rebuild_studio_checks()

        btns = ttk.Frame(f)
        btns.pack(anchor="w", pady=6)
        RoundButton(btns, text="① Sync catalogue from Sonar", kind="teal",
                   command=self._on_sync).grid(row=0, column=0)
        self.fetch_btn = RoundButton(btns, text="② Fetch selected studios",
                                    kind="accent", command=self._on_fetch)
        self.fetch_btn.grid(row=0, column=1, padx=8)

        self.progress = ttk.Progressbar(f, mode="determinate")
        self.progress.pack(fill="x", pady=(6, 6))

        self.log_box = tk.Text(f, height=15, state="disabled", relief="flat",
                               bg=CONSOLE_BG, fg=CONSOLE_FG, insertbackground=CONSOLE_FG,
                               font=("Consolas", 9), padx=8, pady=6)
        self.log_box.pack(fill="both", expand=True)
        if self.cat:
            self.log(f"Loaded cached catalogue: {len(self.cat)} projects. "
                     "Sync again to refresh, or configure the Scope tab.")
        else:
            self.log("No catalogue yet — click '① Sync catalogue from Sonar' first.")

    def _rebuild_studio_checks(self):
        for w in self.studio_check_frame.winfo_children():
            w.destroy()
        self.studio_vars.clear()
        counts = self.smap.studio_counts(self.studios)
        for i, s in enumerate(self.studios):
            disabled = s in self.disabled
            var = tk.BooleanVar(value=not disabled)
            self.studio_vars[s] = var
            label = f"{s}   ({counts.get(s, 0)} projects)"
            if disabled:
                label += "   — disabled"
            ttk.Checkbutton(self.studio_check_frame, text=label, variable=var,
                            state="disabled" if disabled else "normal"
                            ).grid(row=i // 2, column=i % 2, sticky="w", padx=(0, 30), pady=2)

    def _selected_studios(self) -> list[str]:
        return [s for s, v in self.studio_vars.items()
                if v.get() and s not in self.disabled]

    # ---- studio manager dialog ----
    def _open_studio_manager(self):
        dlg = tk.Toplevel(self)
        dlg.title("Manage studios")
        dlg.geometry("400x380")
        dlg.configure(bg=BG)
        dlg.transient(self)
        dlg.grab_set()

        ttk.Label(dlg, text="Studios  (✓ active · ✗ disabled)",
                  style="Section.TLabel").pack(anchor="w", padx=12, pady=(12, 4))
        lb = tk.Listbox(dlg, height=10, font=("Segoe UI", 10), activestyle="none",
                        relief="flat", highlightthickness=1, highlightbackground=BORDER)
        lb.pack(fill="both", expand=True, padx=12)

        def refresh_lb():
            lb.delete(0, "end")
            for s in self.studios:
                lb.insert("end", f"{'✗' if s in self.disabled else '✓'}   {s}")

        def selected():
            sel = lb.curselection()
            return self.studios[sel[0]] if sel else None

        entry_var = tk.StringVar()
        row = ttk.Frame(dlg)
        row.pack(fill="x", padx=12, pady=8)
        ttk.Entry(row, textvariable=entry_var, width=24).pack(side="left")

        def add():
            name = entry_var.get().strip()
            if name and name not in self.studios:
                self.studios.append(name)
                entry_var.set(""); self._persist_studios(); refresh_lb()

        def rename():
            old = selected()
            if not old:
                return
            new = simpledialog.askstring("Rename studio", f"New name for '{old}':",
                                         initialvalue=old, parent=dlg)
            if not new or new.strip() == old:
                return
            new = new.strip()
            self.studios[self.studios.index(old)] = new
            if old in self.disabled:
                self.disabled.discard(old); self.disabled.add(new)
            n = self.smap.rename_studio(old, new); self.smap.save()
            self._persist_studios(); refresh_lb()
            self.log(f"Renamed studio '{old}' → '{new}' ({n} projects repointed).")

        def remove():
            s = selected()
            if not s:
                return
            n = sum(1 for r in self.smap.rows.values() if r["Studio"] == s)
            if not messagebox.askyesno("Remove studio",
                                       f"Remove '{s}'?\n{n} project(s) move to "
                                       f"'{config.UNASSIGNED}'.", parent=dlg):
                return
            self.smap.rename_studio(s, config.UNASSIGNED); self.smap.save()
            self.studios.remove(s); self.disabled.discard(s)
            self._persist_studios(); refresh_lb()

        def toggle_disabled():
            s = selected()
            if not s:
                return
            self.disabled.discard(s) if s in self.disabled else self.disabled.add(s)
            self._persist_studios(); refresh_lb()

        RoundButton(row, text="Add", kind="accent", command=add).pack(side="left", padx=6)
        br = ttk.Frame(dlg)
        br.pack(fill="x", padx=12, pady=(0, 8))
        RoundButton(br, text="Rename", kind="plain", command=rename).pack(side="left")
        RoundButton(br, text="Enable/Disable", kind="plain",
                   command=toggle_disabled).pack(side="left", padx=6)
        RoundButton(br, text="Remove", kind="plain", command=remove).pack(side="left")
        RoundButton(dlg, text="Close", kind="accent",
                   command=dlg.destroy).pack(pady=8)
        refresh_lb()

    def _persist_studios(self):
        config.save_studios({"studios": self.studios, "disabled": sorted(self.disabled)})
        self._rebuild_studio_checks()
        for cb in (getattr(self, "map_filter_cb", None), getattr(self, "scope_filter_cb", None),
                   getattr(self, "dash_studio_cb", None)):
            if cb:
                cb.configure(values=["(all)"] + self._studio_choices())
        if getattr(self, "assign_cb", None):
            self.assign_cb.configure(values=self._studio_choices())
        if getattr(self, "gen_studio_cb", None):
            self.gen_studio_cb.configure(values=["All studios"] + self.studios)
        if hasattr(self, "email_grid"):
            self._rebuild_email_grid()
        if getattr(self, "preview_studio_cb", None):
            self.preview_studio_cb.configure(values=self.studios)
        self._refresh_mapping_tree()
        self._refresh_scope_tree()
        self._update_footer()

    def _on_sync(self):
        threading.Thread(target=self._sync_worker, daemon=True).start()

    def _sync_worker(self):
        try:
            self.log("Connecting to SonarQube — discovering projects and branches…")
            client = SonarClient()

            def cb(done, total, name):
                if done % 10 == 0 or done == total:
                    self.after(0, lambda: self.progress.configure(maximum=total, value=done))
                    self.log(f"  [{done}/{total}] {name}")

            self.cat = build_catalogue(client, cb)
            scope.save_catalogue(self.cat)
            added_map = self.smap.sync_with_catalogue(
                [(v["key"], k) for k, v in self.cat.items()])
            self.smap.save()
            added_sel = self.bsel.seed_from_catalogue(self.cat)
            self.bsel.save()
            self.log(f"Catalogue: {len(self.cat)} projects. New in mapping: "
                     f"{len(added_map)}. Default branch selections added: {added_sel}.")
            self.after(0, self._rebuild_studio_checks)
            self.after(0, self._refresh_mapping_tree)
            self.after(0, self._refresh_scope_tree)
            self.after(0, self._update_footer)
        except Exception as e:  # noqa: BLE001
            self.log(f"ERROR during sync: {e}")

    def _on_fetch(self):
        studios = self._selected_studios()
        if not studios:
            messagebox.showwarning("Nothing selected", "Select at least one studio.")
            return
        if not self.cat:
            messagebox.showwarning("No catalogue", "Click 'Sync catalogue from Sonar' first.")
            return
        self.fetch_btn.configure(state="disabled")
        threading.Thread(target=self._fetch_worker, args=(studios,), daemon=True).start()

    def _fetch_worker(self, studios):
        try:
            client = SonarClient()
            combos = []
            for s in studios:
                for name in self.smap.projects_for(s):
                    info = self.cat.get(name)
                    if not info:
                        continue
                    br = self.bsel.selected_branch(name, self.cat)
                    if br:
                        combos.append((s, name, info["key"], br))
            if not combos:
                self.log("No projects to fetch. Configure the Scope tab.")
                return
            total = len(combos)
            self.after(0, lambda: self.progress.configure(maximum=total, value=0))
            self.results = {s: [] for s in studios}
            for i, (s, name, key, br) in enumerate(combos, 1):
                c = client.severity_counts(key, br)
                rec = {"project": name, "key": key, "branch": br,
                       "c": c["Critical"], "h": c["High"], "m": c["Medium"], "l": c["Low"]}
                self.results[s].append(rec)
                self.scope_cache[name] = rec
                self.after(0, lambda v=i: self.progress.configure(value=v))
                self.log(f"  [{i}/{total}] {s} · {name} @ {br} — "
                         f"C={c['Critical']} H={c['High']} M={c['Medium']} L={c['Low']}")
            self.log("Fetch complete. See Scope for stats, or go to Generate.")
            self.after(0, self._refresh_scope_tree)
            self.after(0, self._refresh_dashboard)
        except Exception as e:  # noqa: BLE001
            self.log(f"ERROR during fetch: {e}")
        finally:
            self.after(0, lambda: self.fetch_btn.configure(state="normal"))

    # ============================================================ TAB 2: Mapping
    def _make_search_bar(self, parent, var, on_change):
        """A styled search toolbar: 🔎 [entry] [✕]  … returns the count label."""
        bar = ttk.Frame(parent, style="Toolbar.TFrame", padding=8)
        bar.pack(fill="x", pady=(6, 0))
        ttk.Label(bar, text="🔎", style="Toolbar.TLabel").pack(side="left", padx=(2, 4))
        ent = ttk.Entry(bar, textvariable=var, width=42, style="Search.TEntry")
        ent.pack(side="left")
        RoundButton(bar, text="✕", kind="plain", bg=TOOLBAR_BG, padx=10, pady=6,
                   command=lambda: var.set("")).pack(side="left", padx=4)
        ttk.Label(bar, text="type any part of a project name",
                  style="Toolbar.TLabel").pack(side="left", padx=8)
        count = ttk.Label(bar, text="", style="Count.TLabel")
        count.pack(side="right", padx=6)
        var.trace_add("write", lambda *_: on_change())
        return count

    @staticmethod
    def _matches(name: str, query: str) -> bool:
        q = query.strip().lower()
        return not q or q in name.lower()

    def _build_mapping_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="2. Project Mapping")

        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="Assign each project to a studio",
                  style="Section.TLabel").pack(side="left")
        RoundButton(top, text="💾 Save mapping", kind="accent",
                   command=self._save_mapping).pack(side="right")
        ttk.Label(top, text="Filter:").pack(side="right", padx=(0, 4))
        self.filter_var = tk.StringVar(value="(all)")
        self.map_filter_cb = ttk.Combobox(top, textvariable=self.filter_var, width=14,
                                          state="readonly",
                                          values=["(all)"] + self._studio_choices())
        self.map_filter_cb.pack(side="right", padx=(0, 8))
        self.filter_var.trace_add("write", lambda *_: self._refresh_mapping_tree())

        # search box
        self.map_search_var = tk.StringVar(value="")
        self.map_count = self._make_search_bar(f, self.map_search_var,
                                               self._refresh_mapping_tree)

        cols = ("Project_Name", "Studio", "Include", "Confidence")
        self.tree = ttk.Treeview(f, columns=cols, show="headings", height=16)
        for c, w in zip(cols, (460, 130, 70, 90)):
            self.tree.heading(c, text=c.replace("_", " "))
            self.tree.column(c, width=w, anchor="w")
        self.tree.tag_configure("odd", background=STRIPE)
        self.tree.pack(fill="both", expand=True, pady=8)

        edit = ttk.Frame(f)
        edit.pack(fill="x")
        ttk.Label(edit, text="Set selected →").pack(side="left")
        # editable combobox: pick an existing studio OR type a NEW one
        self.assign_var = tk.StringVar(value=self.studios[0] if self.studios else config.UNASSIGNED)
        self.assign_cb = ttk.Combobox(edit, textvariable=self.assign_var, width=18,
                                      values=self._studio_choices())   # NOT readonly
        self.assign_cb.pack(side="left", padx=6)
        RoundButton(edit, text="Assign (new name OK)", kind="accent",
                   command=self._assign_studio).pack(side="left")
        RoundButton(edit, text="Toggle Include", kind="plain",
                   command=self._toggle_include).pack(side="left", padx=6)
        ttk.Label(f, text="Tip: type a brand-new studio name in the box and click Assign — "
                          "it is created and saved for next time.",
                  style="Muted.TLabel").pack(anchor="w", pady=(4, 0))
        self._refresh_mapping_tree()

    def _refresh_mapping_tree(self):
        if not hasattr(self, "tree"):
            return
        self.tree.delete(*self.tree.get_children())
        flt = self.filter_var.get()
        query = self.map_search_var.get() if hasattr(self, "map_search_var") else ""
        i = 0
        total = len(self.smap.rows)
        for name in sorted(self.smap.rows):
            r = self.smap.rows[name]
            if flt != "(all)" and r["Studio"] != flt:
                continue
            if not self._matches(name, query):
                continue
            self.tree.insert("", "end", iid=name,
                             values=(name, r["Studio"], r.get("Include", "Yes"),
                                     r.get("Confidence", "")),
                             tags=("odd",) if i % 2 else ())
            i += 1
        if hasattr(self, "map_count"):
            self.map_count.configure(text=f"{i} shown / {total} total")

    def _assign_studio(self):
        new_studio = self.assign_var.get().strip()
        if not new_studio:
            return
        # create the studio if it does not exist yet
        if new_studio not in self.studios and new_studio != config.UNASSIGNED:
            self.studios.append(new_studio)
            self._persist_studios()
            self.log(f"Created new studio '{new_studio}'.")
        for name in self.tree.selection():
            self.smap.rows[name]["Studio"] = new_studio
            self.smap.rows[name]["Confidence"] = "manual"
        self.smap.save()
        self._refresh_mapping_tree()

    def _toggle_include(self):
        for name in self.tree.selection():
            cur = str(self.smap.rows[name].get("Include", "Yes")).lower()
            self.smap.rows[name]["Include"] = "No" if cur in ("yes", "y", "true", "1") else "Yes"
        self._refresh_mapping_tree()

    def _save_mapping(self):
        self.smap.save()
        messagebox.showinfo("Saved", f"Mapping saved to\n{config.STUDIO_MAPPING_CSV}")

    # ============================================================ TAB 3: Scope
    def _build_scope_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="3. Scope (Projects & Branches)")

        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="Pick one branch per project, then Refresh to see its vulnerabilities",
                  style="Section.TLabel").pack(side="left")
        RoundButton(top, text="💾 Save scope", kind="plain",
                   command=self._save_scope).pack(side="right")
        RoundButton(top, text="🔄 Refresh stats", kind="teal",
                   command=self._on_scope_refresh).pack(side="right", padx=6)
        ttk.Label(top, text="Studio:").pack(side="right", padx=(0, 4))
        default_studio = self.studios[0] if self.studios else "(all)"
        self.scope_filter = tk.StringVar(value=default_studio)
        self.scope_filter_cb = ttk.Combobox(top, textvariable=self.scope_filter, width=15,
                                            state="readonly",
                                            values=["(all)"] + self._studio_choices())
        self.scope_filter_cb.pack(side="right", padx=(0, 8))
        self.scope_filter.trace_add("write", lambda *_: self._refresh_scope_tree())

        # search box
        self.scope_search_var = tk.StringVar(value="")
        self.scope_count = self._make_search_bar(f, self.scope_search_var,
                                                 self._refresh_scope_tree)

        cols = ("studio", "branch", "scan", "inc", "crit", "high", "med", "low")
        self.scope_tree = ttk.Treeview(f, columns=cols, show="tree headings", height=15)
        self.scope_tree.heading("#0", text="Project")
        self.scope_tree.heading("studio", text="Studio")
        self.scope_tree.heading("branch", text="Branch  ▼")
        self.scope_tree.heading("scan", text="Last Scan")
        self.scope_tree.heading("inc", text="Include")
        for c, t in (("crit", "Critical"), ("high", "High"), ("med", "Medium"), ("low", "Low")):
            self.scope_tree.heading(c, text=t)
        self.scope_tree.column("#0", width=330, anchor="w")
        self.scope_tree.column("studio", width=100, anchor="w")
        self.scope_tree.column("branch", width=220, anchor="w")
        self.scope_tree.column("scan", width=110, anchor="center")
        self.scope_tree.column("inc", width=64, anchor="center")
        for c in ("crit", "high", "med", "low"):
            self.scope_tree.column(c, width=66, anchor="center")
        self.scope_tree.tag_configure("odd", background=STRIPE)
        self.scope_tree.tag_configure("crit", background=CRIT_BG)
        self.scope_tree.tag_configure("high", background=HIGH_BG)
        self.scope_tree.tag_configure("unscanned", background=UNSCANNED_BG)
        self.scope_tree.pack(fill="both", expand=True, pady=8)
        self.scope_tree.bind("<Button-1>", self._on_scope_click)

        bottom = ttk.Frame(f)
        bottom.pack(fill="x")
        self.scope_status = ttk.Label(bottom, text="Click the Branch cell to choose a branch. "
                                                   "Click Include to toggle. Grey rows = branch "
                                                   "not scanned yet in Sonar (stats will show 0).",
                                      style="Muted.TLabel")
        self.scope_status.pack(side="left")
        self._refresh_scope_tree()

    def _scope_projects(self):
        flt = self.scope_filter.get()
        query = self.scope_search_var.get() if hasattr(self, "scope_search_var") else ""
        for name in sorted(self.cat):
            studio = self.smap.studio_of(name)
            if flt != "(all)" and studio != flt:
                continue
            if not self._matches(name, query):
                continue
            yield name, studio

    def _branch_last_scan(self, project: str, branch: str) -> str:
        """Last analysis date (ISO string) for project/branch, or '' if never scanned."""
        info = self.cat.get(project, {})
        for b in info.get("branches", []):
            if b.get("name") == branch:
                return b.get("lastScan", "") or ""
        return ""

    def _refresh_scope_tree(self):
        if not hasattr(self, "scope_tree"):
            return
        self._close_branch_editor()
        self.scope_tree.delete(*self.scope_tree.get_children())
        if not self.cat:
            self.scope_tree.insert("", "end", text="(sync the catalogue first — tab 1)")
            return
        tc = th = tm = tl = unscanned = 0
        for i, (name, studio) in enumerate(self._scope_projects()):
            branch = self.bsel.selected_branch(name, self.cat)
            last_scan = self._branch_last_scan(name, branch)
            scanned = bool(last_scan)
            scan_display = last_scan if scanned else "⚠ Not scanned"
            if not scanned:
                unscanned += 1
            inc = CHECK if (self.smap.included(name) and branch) else UNCHECK
            cache = self.scope_cache.get(name)
            if cache and cache.get("branch") == branch:
                cvals = (cache["c"], cache["h"], cache["m"], cache["l"])
                tc += cache["c"]; th += cache["h"]; tm += cache["m"]; tl += cache["l"]
            else:
                cvals = ("", "", "", "")
            tags = ["odd"] if i % 2 else []
            if not scanned:
                tags = ["unscanned"]
            elif cache and cache.get("branch") == branch and cache["c"]:
                tags = ["crit"]
            elif cache and cache.get("branch") == branch and cache["h"]:
                tags = ["high"]
            self.scope_tree.insert("", "end", iid=name, text=name,
                                   values=(studio, branch, scan_display, inc, *cvals), tags=tags)
        self.scope_status.configure(
            text=f"Shown totals — Critical {tc} · High {th} · Medium {tm} · Low {tl}"
                 f"   ·   {unscanned} branch(es) not yet scanned   (Refresh to update)")
        if hasattr(self, "scope_count"):
            self.scope_count.configure(
                text=f"{len(self.scope_tree.get_children())} shown / {len(self.cat)} total")

    def _on_scope_click(self, event):
        if self.scope_tree.identify("region", event.x, event.y) != "cell":
            return
        col = self.scope_tree.identify_column(event.x)
        iid = self.scope_tree.identify_row(event.y)
        if not iid or iid not in self.cat:
            return
        if col == "#2":          # Branch column -> dropdown editor
            self._edit_branch(iid)
        elif col == "#4":        # Include column -> toggle
            cur = self.smap.included(iid)
            self.smap.rows.setdefault(iid, {"Project_Name": iid,
                                            "Studio": self.smap.studio_of(iid),
                                            "Include": "Yes", "Confidence": "manual",
                                            "Source": "scope"})
            self.smap.rows[iid]["Include"] = "No" if cur else "Yes"
            self._refresh_scope_tree()

    def _close_branch_editor(self):
        if self._branch_editor is not None:
            try:
                self._branch_editor.destroy()
            except tk.TclError:
                pass
            self._branch_editor = None

    def _edit_branch(self, project):
        self._close_branch_editor()
        bbox = self.scope_tree.bbox(project, "branch")
        if not bbox:
            return
        x, y, w, h = bbox
        branches = [b["name"] for b in self.cat[project].get("branches", [])]
        var = tk.StringVar(value=self.bsel.selected_branch(project, self.cat))
        cb = ttk.Combobox(self.scope_tree, textvariable=var, values=branches,
                          state="readonly")
        cb.place(x=x, y=y, width=max(w, 220), height=h)
        cb.focus_set()
        cb.event_generate("<Button-1>")

        def commit(_=None):
            val = var.get()
            if val:
                self.bsel.set_single(project, val)
                self.scope_tree.set(project, "branch", val)
                last_scan = self._branch_last_scan(project, val)
                self.scope_tree.set(project, "scan", last_scan if last_scan else "⚠ Not scanned")
                self.scope_tree.set(project, "crit", "")
                self.scope_tree.set(project, "high", "")
                self.scope_tree.set(project, "med", "")
                self.scope_tree.set(project, "low", "")
                if not last_scan:
                    self.scope_tree.item(project, tags=["unscanned"])
                else:
                    self.scope_tree.item(project, tags=[])
            self._close_branch_editor()

        cb.bind("<<ComboboxSelected>>", commit)
        cb.bind("<FocusOut>", lambda e: self._close_branch_editor())
        cb.bind("<Escape>", lambda e: self._close_branch_editor())
        self._branch_editor = cb

    def _on_scope_refresh(self):
        if not self.cat:
            messagebox.showwarning("No catalogue", "Sync the catalogue first (tab 1).")
            return
        threading.Thread(target=self._scope_refresh_worker, daemon=True).start()

    def _scope_refresh_worker(self):
        try:
            client = SonarClient()
            targets = [(name, studio) for name, studio in self._scope_projects()
                       if self.smap.included(name)]
            total = len(targets)
            if not total:
                self.log("Scope refresh: nothing included for this studio.")
                return
            self.after(0, lambda: self.progress.configure(maximum=total, value=0))
            by_studio: dict[str, list[dict]] = {}
            for i, (name, studio) in enumerate(targets, 1):
                info = self.cat.get(name)
                branch = self.bsel.selected_branch(name, self.cat)
                if not info or not branch:
                    continue
                c = client.severity_counts(info["key"], branch)
                rec = {"project": name, "key": info["key"], "branch": branch,
                       "c": c["Critical"], "h": c["High"], "m": c["Medium"], "l": c["Low"]}
                self.scope_cache[name] = rec
                by_studio.setdefault(studio, []).append(rec)
                self.after(0, lambda v=i: self.progress.configure(value=v))
                self.log(f"  scope [{i}/{total}] {name} @ {branch} — "
                         f"C={c['Critical']} H={c['High']} M={c['Medium']} L={c['Low']}")
            # merge into results so Generate/Email can use it
            for studio, recs in by_studio.items():
                self.results[studio] = recs
            self.after(0, self._refresh_scope_tree)
            self.after(0, self._refresh_dashboard)
            self.log("Scope refresh complete.")
        except Exception as e:  # noqa: BLE001
            self.log(f"ERROR during scope refresh: {e}")

    def _save_scope(self):
        self.smap.save()
        self.bsel.save()
        messagebox.showinfo("Saved", "Scope saved (studio_mapping.csv + branch_selection.csv).")

    # ============================================================ TAB 4: Generate
    def _build_generate_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="4. Generate Report")

        ttk.Label(f, text="Generate the quarterly / monthly workbook",
                  style="Section.TLabel").pack(anchor="w")

        row = ttk.Frame(f)
        row.pack(fill="x", pady=8)

        ttk.Label(row, text="Studio:").grid(row=0, column=0, sticky="w", pady=3)
        self.gen_studio_var = tk.StringVar(value="All studios")
        self.gen_studio_cb = ttk.Combobox(row, textvariable=self.gen_studio_var, width=20,
                                          state="readonly",
                                          values=["All studios"] + self.studios)
        self.gen_studio_cb.grid(row=0, column=1, sticky="w", padx=6)

        ttk.Label(row, text="Period type:").grid(row=1, column=0, sticky="w", pady=3)
        self.ptype_var = tk.StringVar(value=self.settings.get("period_type", "Monthly"))
        ptype = ttk.Combobox(row, textvariable=self.ptype_var, width=20, state="readonly",
                             values=config.PERIOD_TYPES)
        ptype.grid(row=1, column=1, sticky="w", padx=6)
        ptype.bind("<<ComboboxSelected>>", lambda *_: self._fill_period_defaults())

        ttk.Label(row, text="Current period:").grid(row=2, column=0, sticky="w", pady=3)
        self.period_var = tk.StringVar(
            value=self.settings.get("period_label")
            or config.default_period_label(self.ptype_var.get()))
        ttk.Entry(row, textvariable=self.period_var, width=22).grid(row=2, column=1, sticky="w", padx=6)
        ttk.Label(row, text="Monthly → August'26 · Quarterly → JQ'26",
                  style="Muted.TLabel").grid(row=2, column=2, sticky="w", padx=6)

        ttk.Label(row, text="Prior period:").grid(row=3, column=0, sticky="w", pady=3)
        prior_default = (self.settings.get("prior_label")
                         or (self.history.quarters()[-1] if self.history.quarters() else "")
                         or config.previous_period_label(self.ptype_var.get()))
        self.prior_var = tk.StringVar(value=prior_default)
        ttk.Combobox(row, textvariable=self.prior_var, width=22,
                     values=self.history.quarters()).grid(row=3, column=1, sticky="w", padx=6)
        RoundButton(row, text="Fill from today", kind="plain",
                   command=self._fill_period_defaults).grid(row=3, column=2, sticky="w", padx=6)

        ttk.Label(row, text="Output folder:").grid(row=4, column=0, sticky="w", pady=3)
        self.outdir_var = tk.StringVar(value=self.settings.get("output_dir", config.DEFAULT_OUTPUT_DIR))
        ttk.Entry(row, textvariable=self.outdir_var, width=52).grid(row=4, column=1, columnspan=2, sticky="w", padx=6)
        RoundButton(row, text="Browse…", kind="plain",
                   command=self._browse_out).grid(row=4, column=3)

        bar = ttk.Frame(f)
        bar.pack(anchor="w", pady=6)
        RoundButton(bar, text="📄 Generate", kind="accent",
                   command=self._on_generate).pack(side="left")
        RoundButton(bar, text="Open output folder", kind="plain",
                   command=self._open_out).pack(side="left", padx=8)
        RoundButton(bar, text="🗄 Backup data now", kind="plain",
                   command=self._backup_now).pack(side="left")

        self.gen_box = tk.Text(f, height=12, state="disabled", relief="flat",
                               bg=CONSOLE_BG, fg=CONSOLE_FG, font=("Consolas", 9), padx=8, pady=6)
        self.gen_box.pack(fill="both", expand=True, pady=8)

    def _fill_period_defaults(self):
        pt = self.ptype_var.get()
        self.period_var.set(config.default_period_label(pt))
        self.prior_var.set(config.previous_period_label(pt))

    def _backup_now(self):
        try:
            path = backup.run_backup()
            self._gen_log(f"Backup created: {path}")
            messagebox.showinfo("Backup", f"Data backed up to:\n{path}")
        except Exception as e:  # noqa: BLE001
            messagebox.showerror("Backup failed", str(e))

    def _browse_out(self):
        d = filedialog.askdirectory(initialdir=self.outdir_var.get() or config.BASE_DIR)
        if d:
            self.outdir_var.set(d)

    def _open_out(self):
        d = self.outdir_var.get()
        if os.path.isdir(d):
            os.startfile(d)  # noqa: S606

    def _gen_log(self, msg):
        self.gen_box.configure(state="normal")
        self.gen_box.insert("end", msg + "\n")
        self.gen_box.see("end")
        self.gen_box.configure(state="disabled")

    def _on_generate(self):
        if not self.results:
            messagebox.showwarning("No data", "Fetch (tab 1) or Refresh stats (tab 3) first.")
            return
        cur = self.period_var.get().strip() or config.default_period_label(self.ptype_var.get())
        prior = self.prior_var.get().strip()
        out_dir = self.outdir_var.get().strip() or config.DEFAULT_OUTPUT_DIR
        self.settings.update({"period_type": self.ptype_var.get(), "period_label": cur,
                              "prior_label": prior, "output_dir": out_dir})
        self._save_settings()

        pick = self.gen_studio_var.get()
        studios = self.studios if pick == "All studios" else [pick]

        self.generated.clear()
        any_done = False
        for studio in studios:
            rows = self.results.get(studio) or []
            if not rows:
                self._gen_log(f"{studio}: no fetched rows, skipped.")
                continue
            for r in rows:
                self.history.record(cur, studio, r["project"], r["branch"],
                                    r["c"], r["h"], r["m"], r["l"])
            path = report.build_workbook(studio, cur, prior, rows, self.history, out_dir)
            self.generated[studio] = path
            t = self._totals(rows)
            self._gen_log(f"{studio}: {os.path.basename(path)}  "
                          f"(C={t['Critical']} H={t['High']} M={t['Medium']} L={t['Low']})")
            any_done = True
        if any_done:
            self.history.save()
            self._gen_log("Done. History updated.")
        else:
            self._gen_log("Nothing generated — fetch data for the chosen studio first.")

    @staticmethod
    def _totals(rows) -> dict:
        t = {"Critical": 0, "High": 0, "Medium": 0, "Low": 0}
        for r in rows:
            t["Critical"] += r["c"]; t["High"] += r["h"]
            t["Medium"] += r["m"]; t["Low"] += r["l"]
        return t

    # ==================================================== TAB 6: Custom Sort
    def _build_sort_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="6. Custom Sort")

        ttk.Label(f, text="Re-sort a report's projects into a custom order",
                  style="Section.TLabel").pack(anchor="w")
        ttk.Label(f, text="Paste your project names below in the order you want them. "
                          "The report's projects, branches and stats are re-sorted to match; "
                          "any project not in your list is appended alphabetically (never dropped).",
                  style="Muted.TLabel").pack(anchor="w", pady=(0, 8))

        row = ttk.Frame(f)
        row.pack(fill="x", pady=4)

        ttk.Label(row, text="Studio:").grid(row=0, column=0, sticky="w", pady=3)
        self.sort_studio_var = tk.StringVar(value=self.studios[0] if self.studios else "")
        self.sort_studio_cb = ttk.Combobox(row, textvariable=self.sort_studio_var, width=20,
                                            state="readonly", values=self.studios)
        self.sort_studio_cb.grid(row=0, column=1, sticky="w", padx=6)

        ttk.Label(row, text="Report file:").grid(row=1, column=0, sticky="w", pady=3)
        self.sort_file_var = tk.StringVar(value="")
        ttk.Entry(row, textvariable=self.sort_file_var, width=52).grid(
            row=1, column=1, columnspan=2, sticky="w", padx=6)
        RoundButton(row, text="Browse…", kind="plain",
                   command=self._browse_sort_file).grid(row=1, column=3)
        ttk.Label(row, text="Pick a generated .xlsx to re-sort — or leave blank to "
                            "re-sort the data generated this session.",
                  style="Muted.TLabel").grid(row=2, column=1, columnspan=3, sticky="w", padx=6)

        ttk.Label(f, text="Project order (one project name per line):",
                  style="Section.TLabel").pack(anchor="w", pady=(8, 2))
        self.sort_text = tk.Text(f, height=12, font=("Consolas", 10), relief="flat",
                                 highlightthickness=1, highlightbackground=BORDER,
                                 wrap="none", padx=6, pady=6)
        self.sort_text.pack(fill="both", expand=True)

        bar = ttk.Frame(f)
        bar.pack(anchor="w", pady=6)
        RoundButton(bar, text="🔀 Sort & Generate", kind="accent",
                   command=self._on_sort).pack(side="left")
        RoundButton(bar, text="Open output folder", kind="plain",
                   command=self._open_out).pack(side="left", padx=8)

        self.sort_box = tk.Text(f, height=6, state="disabled", relief="flat",
                                bg=CONSOLE_BG, fg=CONSOLE_FG, font=("Consolas", 9), padx=8, pady=6)
        self.sort_box.pack(fill="x", pady=8)

    def _browse_sort_file(self):
        init = self.outdir_var.get() if hasattr(self, "outdir_var") else config.BASE_DIR
        p = filedialog.askopenfilename(
            initialdir=init or config.BASE_DIR,
            title="Select a generated report to re-sort",
            filetypes=[("Excel workbook", "*.xlsx"), ("All files", "*.*")])
        if p:
            self.sort_file_var.set(p)

    def _sort_log(self, msg):
        self.sort_box.configure(state="normal")
        self.sort_box.insert("end", msg + "\n")
        self.sort_box.see("end")
        self.sort_box.configure(state="disabled")

    def _on_sort(self):
        studio = self.sort_studio_var.get().strip()
        if not studio:
            messagebox.showwarning("No studio", "Pick a studio first.")
            return
        order = [ln.strip() for ln in self.sort_text.get("1.0", "end").splitlines() if ln.strip()]
        if not order:
            messagebox.showwarning("No project list",
                                   "Paste the project names (one per line) to sort by.")
            return
        out_dir = (self.outdir_var.get().strip()
                   if hasattr(self, "outdir_var") else "") or config.DEFAULT_OUTPUT_DIR
        src = self.sort_file_var.get().strip()
        try:
            if src:
                if not os.path.isfile(src):
                    messagebox.showerror("File not found", f"No such file:\n{src}")
                    return
                path = report.resort_report_file(studio, src, order, out_dir)
                self._sort_log(f"{studio}: re-sorted from file → {os.path.basename(path)} "
                               f"({len(order)} projects in list)")
            else:
                rows = self.results.get(studio) or []
                if not rows:
                    messagebox.showwarning(
                        "No data",
                        f"No data for {studio} in this session.\n\nEither fetch/generate it "
                        f"first (tabs 1/4), or use Browse to pick an existing report file.")
                    return
                cur = ((self.period_var.get().strip() if hasattr(self, "period_var") else "")
                       or config.default_period_label(self.ptype_var.get()))
                prior = self.prior_var.get().strip() if hasattr(self, "prior_var") else ""
                path = report.build_workbook(studio, cur, prior, rows, self.history,
                                             out_dir, project_order=order, tag="sorted")
                self._sort_log(f"{studio}: re-sorted session data → {os.path.basename(path)} "
                               f"({len(order)} projects in list)")
            self.generated[studio] = path
            messagebox.showinfo("Sorted", f"Saved:\n{path}")
        except Exception as e:  # noqa: BLE001
            messagebox.showerror("Sort failed", str(e))
            self._sort_log(f"{studio}: ERROR — {e}")

    # ============================================================ TAB 5: Email
    def _build_email_tab(self, nb):
        f = ttk.Frame(nb, padding=12)
        nb.add(f, text="5. Email")

        ttk.Label(f, text="Recipients per studio (comma-separated)",
                  style="Section.TLabel").pack(anchor="w", pady=(0, 6))
        self.email_grid = ttk.Frame(f)
        self.email_grid.pack(fill="x")
        self.recip_vars = {}
        self._rebuild_email_grid()

        # ---- Preview & Edit one studio's email before it goes anywhere ----
        prev = ttk.Frame(f)
        prev.pack(fill="x", pady=(10, 4))
        ttk.Label(prev, text="Preview & edit:", style="Section.TLabel").pack(side="left")
        self.preview_studio_var = tk.StringVar(value=self.studios[0] if self.studios else "")
        self.preview_studio_cb = ttk.Combobox(prev, textvariable=self.preview_studio_var,
                                              width=18, state="readonly", values=self.studios)
        self.preview_studio_cb.pack(side="left", padx=6)
        RoundButton(prev, text="👁  Preview & Edit…", kind="teal",
                   command=self._open_email_preview).pack(side="left")
        ttk.Label(f, text="Preview opens an editable window (recipients, subject, message) "
                          "→ then Open draft in Outlook or Send.",
                  style="Muted.TLabel").pack(anchor="w")

        self.send_direct = tk.BooleanVar(value=self.settings.get("send_directly", False))
        ttk.Checkbutton(f, text="Bulk send immediately (default: open a draft in Outlook to review)",
                        variable=self.send_direct).pack(anchor="w", pady=8)
        RoundButton(f, text="✉  Prepare emails for ALL generated studios", kind="accent",
                   command=self._on_email).pack(anchor="w")

        self.email_box = tk.Text(f, height=7, state="disabled", relief="flat",
                                 bg=CONSOLE_BG, fg=CONSOLE_FG, font=("Consolas", 9), padx=8, pady=6)
        self.email_box.pack(fill="both", expand=True, pady=10)

    def _open_email_preview(self):
        studio = self.preview_studio_var.get()
        if not studio:
            return
        path = self.generated.get(studio)
        if not path:
            messagebox.showwarning("Not generated",
                                   f"Generate the report for {studio} first (tab 4).")
            return
        period = self.period_var.get().strip()
        rows = self.results.get(studio, [])
        totals = self._totals(rows)
        proj_count = len({r["project"] for r in rows})
        rec = self.settings.get("recipients", {}).get(studio, {})
        to0 = self.recip_vars.get(studio, (None, None))[0]
        cc0 = self.recip_vars.get(studio, (None, None))[1]
        to_default = to0.get() if to0 else rec.get("to", "")
        cc_default = cc0.get() if cc0 else rec.get("cc", "")

        subj_tmpl = self.settings.get("email_subject_tmpl",
                                      "SonarQube Vulnerability Report — {studio} — {period}")
        msg_tmpl = self.settings.get("email_message_tmpl", "")
        try:
            subject0 = subj_tmpl.format(studio=studio, period=period)
        except Exception:  # noqa: BLE001
            subject0 = subj_tmpl
        if msg_tmpl:
            try:
                message0 = msg_tmpl.format(studio=studio, period=period)
            except Exception:  # noqa: BLE001
                message0 = msg_tmpl
        else:
            message0 = mailer.default_message(studio, period)

        dlg = tk.Toplevel(self)
        dlg.title(f"Preview & Edit — {studio}")
        dlg.geometry("640x560")
        dlg.configure(bg=BG)
        dlg.transient(self)
        dlg.grab_set()

        frm = ttk.Frame(dlg, padding=12)
        frm.pack(fill="both", expand=True)

        def field(label, value, width=70):
            ttk.Label(frm, text=label, style="Section.TLabel").pack(anchor="w")
            v = tk.StringVar(value=value)
            ttk.Entry(frm, textvariable=v, width=width).pack(fill="x", pady=(0, 8))
            return v

        to_var = field("To (comma-separated):", to_default)
        cc_var = field("Cc:", cc_default)
        subj_var = field("Subject:", subject0)

        ttk.Label(frm, text="Message (editable):", style="Section.TLabel").pack(anchor="w")
        msg_txt = tk.Text(frm, height=8, font=("Segoe UI", 10), relief="flat",
                          highlightthickness=1, highlightbackground=BORDER,
                          wrap="word", padx=6, pady=6)
        msg_txt.insert("1.0", message0)
        msg_txt.pack(fill="both", expand=True, pady=(0, 6))

        info = (f"Attachment: {os.path.basename(path)}   |   "
                f"Auto stats table appended → C {totals['Critical']} · H {totals['High']} "
                f"· M {totals['Medium']} · L {totals['Low']}  ({proj_count} projects)")
        ttk.Label(frm, text=info, style="Muted.TLabel").pack(anchor="w")

        save_tmpl = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm, text="Save this subject & message as my default template "
                                  "(use {studio} / {period} as placeholders)",
                        variable=save_tmpl).pack(anchor="w", pady=(4, 8))

        def do(send: bool):
            to = to_var.get().strip()
            cc = cc_var.get().strip()
            subject = subj_var.get().strip()
            message = msg_txt.get("1.0", "end").rstrip("\n")
            if not to:
                messagebox.showwarning("No recipient", "Enter at least one 'To' address.",
                                       parent=dlg)
                return
            # persist recipients back into the tab + settings
            if studio in self.recip_vars:
                self.recip_vars[studio][0].set(to)
                self.recip_vars[studio][1].set(cc)
            self.settings.setdefault("recipients", {})[studio] = {"to": to, "cc": cc}
            if save_tmpl.get():
                self.settings["email_subject_tmpl"] = subj_var.get()
                self.settings["email_message_tmpl"] = message
            self._save_settings()

            body = mailer.build_html_body(studio, period, totals, proj_count, message=message)
            result = mailer.send_report(to, cc, subject, body, [path], display=not send)
            self._email_log(f"{studio}: {result}")
            dlg.destroy()

        btns = ttk.Frame(frm)
        btns.pack(fill="x", pady=6)
        RoundButton(btns, text="📝 Open draft in Outlook (edit more & send there)",
                   kind="accent", command=lambda: do(False)).pack(side="left")
        RoundButton(btns, text="✉ Send now", kind="teal",
                   command=lambda: do(True)).pack(side="left", padx=6)
        RoundButton(btns, text="Cancel", kind="plain", command=dlg.destroy).pack(side="right")

    def _rebuild_email_grid(self):
        for w in self.email_grid.winfo_children():
            w.destroy()
        for j, t in enumerate(("Studio", "To", "Cc")):
            ttk.Label(self.email_grid, text=t, style="Section.TLabel"
                      ).grid(row=0, column=j, sticky="w", padx=4)
        rec = self.settings.get("recipients", {})
        new_vars = {}
        for i, s in enumerate(self.studios, 1):
            ttk.Label(self.email_grid, text=s).grid(row=i, column=0, sticky="w", pady=2)
            old = self.recip_vars.get(s)
            tov = tk.StringVar(value=(old[0].get() if old else rec.get(s, {}).get("to", "")))
            ccv = tk.StringVar(value=(old[1].get() if old else rec.get(s, {}).get("cc", "")))
            ttk.Entry(self.email_grid, textvariable=tov, width=46).grid(row=i, column=1, padx=4)
            ttk.Entry(self.email_grid, textvariable=ccv, width=30).grid(row=i, column=2, padx=4)
            new_vars[s] = (tov, ccv)
        self.recip_vars = new_vars

    def _email_log(self, msg):
        self.email_box.configure(state="normal")
        self.email_box.insert("end", msg + "\n")
        self.email_box.see("end")
        self.email_box.configure(state="disabled")

    def _on_email(self):
        if not self.generated:
            messagebox.showwarning("No reports", "Generate workbooks first (tab 4).")
            return
        rec = {}
        for s, (tov, ccv) in self.recip_vars.items():
            rec[s] = {"to": tov.get().strip(), "cc": ccv.get().strip()}
        self.settings["recipients"] = rec
        self.settings["send_directly"] = self.send_direct.get()
        self._save_settings()

        period = self.period_var.get().strip()
        subj_tmpl = self.settings.get("email_subject_tmpl",
                                      "SonarQube Vulnerability Report — {studio} — {period}")
        msg_tmpl = self.settings.get("email_message_tmpl", "")
        for studio, path in self.generated.items():
            to = rec.get(studio, {}).get("to", "")
            cc = rec.get(studio, {}).get("cc", "")
            if not to:
                self._email_log(f"{studio}: no 'To' address, skipped.")
                continue
            rows = self.results.get(studio, [])
            totals = self._totals(rows)
            try:
                subject = subj_tmpl.format(studio=studio, period=period)
            except Exception:  # noqa: BLE001
                subject = subj_tmpl
            message = None
            if msg_tmpl:
                try:
                    message = msg_tmpl.format(studio=studio, period=period)
                except Exception:  # noqa: BLE001
                    message = msg_tmpl
            body = mailer.build_html_body(studio, period, totals,
                                          len({r['project'] for r in rows}), message=message)
            result = mailer.send_report(to, cc, subject, body, [path],
                                        display=not self.send_direct.get())
            self._email_log(f"{studio}: {result}")

    # ============================================================ TAB 7: Dashboard
    def _build_dashboard_tab(self, nb):
        f = ttk.Frame(nb, padding=0)
        nb.add(f, text="7. Dashboard")

        top = ttk.Frame(f, padding=(12, 10))
        top.pack(fill="x")
        ttk.Label(top, text="Visual summary — included projects & their selected "
                            "branch only (from Scope)", style="Section.TLabel").pack(side="left")
        RoundButton(top, text="🔄 Refresh dashboard", kind="teal",
                   command=self._refresh_dashboard).pack(side="right")
        ttk.Label(top, text="Studio:").pack(side="right", padx=(0, 4))
        self.dash_studio_var = tk.StringVar(value="(all)")
        self.dash_studio_cb = ttk.Combobox(top, textvariable=self.dash_studio_var, width=15,
                                           state="readonly",
                                           values=["(all)"] + self._studio_choices())
        self.dash_studio_cb.pack(side="right", padx=(0, 8))
        self.dash_studio_var.trace_add("write", lambda *_: self._refresh_dashboard())

        outer = tk.Frame(f, bg=BG)
        outer.pack(fill="both", expand=True)
        self.dash_canvas = tk.Canvas(outer, bg=BG, highlightthickness=0)
        vsb = ttk.Scrollbar(outer, orient="vertical", command=self.dash_canvas.yview)
        self.dash_canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side="right", fill="y")
        self.dash_canvas.pack(side="left", fill="both", expand=True)

        self.dash_body = ttk.Frame(self.dash_canvas, padding=(12, 4, 12, 20))
        body_id = self.dash_canvas.create_window((0, 0), window=self.dash_body, anchor="nw")
        self.dash_body.bind("<Configure>", lambda e: self.dash_canvas.configure(
            scrollregion=self.dash_canvas.bbox("all")))
        self.dash_canvas.bind("<Configure>", lambda e: self.dash_canvas.itemconfig(
            body_id, width=e.width))

        def _wheel(e):
            self.dash_canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")
        self.dash_canvas.bind("<Enter>", lambda e: self.dash_canvas.bind_all("<MouseWheel>", _wheel))
        self.dash_canvas.bind("<Leave>", lambda e: self.dash_canvas.unbind_all("<MouseWheel>"))

        # ---- KPI cards ----
        kpi_row = ttk.Frame(self.dash_body)
        kpi_row.pack(fill="x", pady=(4, 14))
        self.kpi_labels = {}
        kpi_specs = [("projects", "Included Projects", TOOLBAR_BG, PRIMARY),
                     ("Critical", "Critical", CRIT_BG, SEV_CRITICAL),
                     ("High", "High", HIGH_BG, SEV_HIGH),
                     ("Medium", "Medium", MED_BG, SEV_MEDIUM),
                     ("Low", "Low", LOW_BG, SEV_LOW)]
        for key, label, cbg, cfg in kpi_specs:
            card = tk.Frame(kpi_row, bg=cbg)
            card.pack(side="left", fill="both", expand=True, padx=6)
            tk.Frame(card, bg=cfg, height=4).pack(fill="x")
            val = tk.Label(card, text="0", bg=cbg, fg=cfg, font=("Segoe UI Semibold", 22))
            val.pack(anchor="w", padx=14, pady=(10, 0))
            tk.Label(card, text=label, bg=cbg, fg=MUTED, font=("Segoe UI", 9)).pack(
                anchor="w", padx=14, pady=(0, 12))
            self.kpi_labels[key] = val

        # ---- severity pie chart + legend ----
        pie_card = ttk.Frame(self.dash_body, style="Card.TFrame", padding=14)
        pie_card.pack(fill="x", pady=(0, 14))
        ttk.Label(pie_card, text="Severity breakdown", style="Section.TLabel",
                  background=CARD).pack(anchor="w")
        pie_row = ttk.Frame(pie_card, style="Card.TFrame")
        pie_row.pack(fill="x", pady=(8, 0))
        self.dash_pie_canvas = tk.Canvas(pie_row, width=220, height=220,
                                         bg=CARD, highlightthickness=0)
        self.dash_pie_canvas.pack(side="left")
        self.dash_pie_legend = ttk.Frame(pie_row, style="Card.TFrame")
        self.dash_pie_legend.pack(side="left", padx=24, fill="both", expand=True)

        # ---- top riskiest projects ----
        top_card = ttk.Frame(self.dash_body, style="Card.TFrame", padding=14)
        top_card.pack(fill="x", pady=(0, 14))
        ttk.Label(top_card, text="Top 10 riskiest projects (Critical + High)",
                  style="Section.TLabel", background=CARD).pack(anchor="w")
        self.dash_top_canvas = tk.Canvas(top_card, height=120, bg=CARD, highlightthickness=0)
        self.dash_top_canvas.pack(fill="x", pady=(8, 0))
        self.dash_top_canvas.bind("<Configure>", lambda e: self._draw_top_projects(width=e.width))

        # ---- trend vs prior period ----
        trend_card = ttk.Frame(self.dash_body, style="Card.TFrame", padding=14)
        trend_card.pack(fill="x", pady=(0, 4))
        ttk.Label(trend_card, text="Trend vs prior period", style="Section.TLabel",
                  background=CARD).pack(anchor="w")
        self.dash_trend_note = ttk.Label(trend_card, text="", style="Muted.TLabel",
                                         background=CARD)
        self.dash_trend_note.pack(anchor="w")
        self.dash_trend_canvas = tk.Canvas(trend_card, height=260, bg=CARD, highlightthickness=0)
        self.dash_trend_canvas.pack(fill="x", pady=(8, 0))
        self.dash_trend_canvas.bind("<Configure>", lambda e: self._draw_trend(width=e.width))

        self._dash_top_rows = []
        self._dash_trend_data = None
        self._refresh_dashboard()

    def _dashboard_rows(self, studio_filter: str) -> list[dict]:
        """Scope-cache rows (included projects, currently selected branch) for a studio filter."""
        out = []
        for name, rec in self.scope_cache.items():
            if not self.smap.included(name):
                continue
            studio = self.smap.studio_of(name)
            if studio_filter != "(all)" and studio != studio_filter:
                continue
            out.append(rec)
        return out

    def _dashboard_history_totals(self, quarter: str, studio_filter: str) -> dict:
        t = {"Critical": 0, "High": 0, "Medium": 0, "Low": 0}
        if not quarter:
            return t
        for r in self.history.rows:
            if r.get("Quarter") != quarter:
                continue
            if studio_filter != "(all)" and r.get("Studio") != studio_filter:
                continue
            t["Critical"] += int(r.get("Critical") or 0)
            t["High"] += int(r.get("High") or 0)
            t["Medium"] += int(r.get("Medium") or 0)
            t["Low"] += int(r.get("Low") or 0)
        return t

    def _refresh_dashboard(self):
        if not hasattr(self, "dash_pie_canvas"):
            return
        studio_filter = self.dash_studio_var.get() if hasattr(self, "dash_studio_var") else "(all)"
        rows = self._dashboard_rows(studio_filter)
        totals = {"Critical": 0, "High": 0, "Medium": 0, "Low": 0}
        for r in rows:
            totals["Critical"] += r["c"]; totals["High"] += r["h"]
            totals["Medium"] += r["m"]; totals["Low"] += r["l"]
        self._dash_totals = totals

        self.kpi_labels["projects"].configure(text=str(len(rows)))
        for key in ("Critical", "High", "Medium", "Low"):
            self.kpi_labels[key].configure(text=str(totals[key]))

        self._draw_severity_pie(totals)

        self._dash_top_rows = sorted(rows, key=lambda r: r["c"] + r["h"], reverse=True)[:10]
        self._draw_top_projects()

        prior_label = self.prior_var.get().strip() if hasattr(self, "prior_var") else ""
        current_label = (self.period_var.get().strip()
                         if hasattr(self, "period_var") else "Current")
        prior_totals = self._dashboard_history_totals(prior_label, studio_filter)
        has_prior = bool(prior_label) and any(prior_totals.values())
        self._dash_trend_data = (prior_totals, totals, prior_label or "n/a", current_label)
        if not prior_label:
            self.dash_trend_note.configure(
                text="Set a 'Prior period' label on the Generate tab to compare.")
        elif not has_prior:
            self.dash_trend_note.configure(
                text=f"No history recorded yet for '{prior_label}' — generate a report "
                     f"once to start tracking trends.")
        else:
            self.dash_trend_note.configure(text="")
        self._draw_trend()

    def _draw_severity_pie(self, totals=None):
        c = self.dash_pie_canvas
        c.delete("all")
        for w in self.dash_pie_legend.winfo_children():
            w.destroy()
        totals = totals if totals is not None else getattr(self, "_dash_totals", {})
        total = sum(totals.values()) if totals else 0
        cx, cy, r = 110, 110, 90
        if total <= 0:
            c.create_text(cx, cy, text="No data yet\nRefresh dashboard", fill=MUTED,
                          font=("Segoe UI", 9), justify="center")
            return
        start = 0
        for label in ("Critical", "High", "Medium", "Low"):
            val = totals.get(label, 0)
            color = SEV_COLORS[label]
            pct = (val / total * 100) if total else 0
            if val > 0:
                extent = 360 * val / total
                c.create_arc(cx - r, cy - r, cx + r, cy + r, start=start, extent=extent,
                            fill=color, outline=CARD, width=2, style="pieslice")
                start += extent
            row = ttk.Frame(self.dash_pie_legend, style="Card.TFrame")
            row.pack(anchor="w", pady=3, fill="x")
            swatch = tk.Canvas(row, width=12, height=12, bg=CARD, highlightthickness=0)
            swatch.pack(side="left", padx=(0, 8))
            swatch.create_oval(1, 1, 11, 11, fill=color, outline=color)
            ttk.Label(row, text=f"{label}: {val}  ({pct:.0f}%)", background=CARD,
                     foreground=TEXT, font=("Segoe UI", 10)).pack(side="left")

    def _draw_top_projects(self, width=None):
        c = self.dash_top_canvas
        rows = getattr(self, "_dash_top_rows", [])
        w = width or c.winfo_width() or 600
        c.delete("all")
        bar_h, gap, margin_t = 22, 10, 10
        label_w = 240
        if not rows:
            c.configure(height=100)
            c.create_text(w / 2, 50, text="No data yet — include & refresh Scope stats first",
                          fill=MUTED, font=("Segoe UI", 9))
            return
        chart_w = max(w - label_w - 70, 60)
        max_val = max((r["c"] + r["h"] for r in rows), default=0) or 1
        height = margin_t * 2 + len(rows) * (bar_h + gap)
        c.configure(height=height)
        y = margin_t
        for r in rows:
            val = r["c"] + r["h"]
            name = r["project"] if len(r["project"]) <= 34 else r["project"][:31] + "…"
            c.create_text(label_w - 10, y + bar_h / 2, anchor="e", text=name,
                          fill=TEXT, font=("Segoe UI", 9))
            x0 = label_w
            cw = int(chart_w * r["c"] / max_val)
            hw = int(chart_w * r["h"] / max_val)
            c.create_rectangle(x0, y, x0 + cw, y + bar_h, fill=SEV_CRITICAL, outline="")
            c.create_rectangle(x0 + cw, y, x0 + cw + hw, y + bar_h, fill=SEV_HIGH, outline="")
            c.create_text(x0 + cw + hw + 8, y + bar_h / 2, anchor="w", text=str(val),
                          fill=TEXT, font=("Segoe UI Semibold", 9))
            y += bar_h + gap

    def _draw_trend(self, width=None):
        c = self.dash_trend_canvas
        w = width or c.winfo_width() or 600
        c.delete("all")
        data = getattr(self, "_dash_trend_data", None)
        if not data:
            c.create_text(w / 2, 120, text="No data yet", fill=MUTED, font=("Segoe UI", 9))
            return
        prior, current, prior_label, current_label = data
        cats = ("Critical", "High", "Medium", "Low")
        max_val = max([prior.get(k, 0) for k in cats] + [current.get(k, 0) for k in cats] + [1])
        margin_l, margin_b, margin_t = 40, 30, 16
        chart_h = 260 - margin_t - margin_b
        n = len(cats)
        group_w = (w - margin_l - 20) / n
        bar_w = max(group_w * 0.28, 10)
        y_base = margin_t + chart_h
        c.create_line(margin_l, margin_t, margin_l, y_base, fill=BORDER)
        c.create_line(margin_l, y_base, w - 10, y_base, fill=BORDER)
        for i, cat in enumerate(cats):
            gx = margin_l + i * group_w + group_w / 2
            color = SEV_COLORS[cat]
            pv, cv = prior.get(cat, 0), current.get(cat, 0)
            ph = int(chart_h * pv / max_val)
            ch = int(chart_h * cv / max_val)
            c.create_rectangle(gx - bar_w - 3, y_base - ph, gx - 3, y_base,
                               fill=color, outline="", stipple="gray50")
            c.create_rectangle(gx + 3, y_base - ch, gx + 3 + bar_w, y_base,
                               fill=color, outline="")
            c.create_text(gx - bar_w / 2 - 3, y_base - ph - 10, text=str(pv),
                          fill=MUTED, font=("Segoe UI", 8))
            c.create_text(gx + bar_w / 2 + 3, y_base - ch - 10, text=str(cv),
                          fill=TEXT, font=("Segoe UI Semibold", 8))
            c.create_text(gx, y_base + 14, text=cat, fill=TEXT, font=("Segoe UI", 9))
        lx = w - 175
        c.create_rectangle(lx, margin_t, lx + 12, margin_t + 10, fill=MUTED,
                           stipple="gray50", outline="")
        c.create_text(lx + 18, margin_t + 5, anchor="w", text=f"Prior ({prior_label})",
                     fill=MUTED, font=("Segoe UI", 8))
        c.create_rectangle(lx, margin_t + 16, lx + 12, margin_t + 26, fill=TEXT, outline="")
        c.create_text(lx + 18, margin_t + 21, anchor="w", text=f"Current ({current_label})",
                     fill=TEXT, font=("Segoe UI", 8))


def main():
    App().mainloop()


if __name__ == "__main__":
    main()
