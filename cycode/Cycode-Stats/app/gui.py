"""
Tkinter desktop UI for Cycode-Stats.

Tabs: 1 Studios & Fetch | 2 Scope (Repositories & Branches) | 3 Generate Report
"""
from __future__ import annotations

import os
import queue
import threading
from datetime import datetime

import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

from . import config, cycode_cli, report, scope
from .studios import StudioMap

CHECK = "☑"
UNCHECK = "☐"

# ---- palette: dark security-console theme -----------------------------
PRIMARY = "#0B1220"       # near-black header navy
PRIMARY_DK = "#05080F"    # footer / deepest shade
ACCENT = "#22D3EE"        # cyan - primary accent
ACCENT_DK = "#0EA5C4"
GOOD = "#34D399"          # green - success / signed-in
BAD = "#F87171"           # red - errors / critical
WARN = "#FBBF24"          # amber - high severity
BG = "#070B14"            # app background
CARD = "#101826"          # card background
CARD_BORDER = "#233047"   # card / input border
TEXT = "#E7EDF7"          # primary text
MUTED = "#8592AC"         # secondary / muted text
STRIPE = "#0C1420"        # alternating row shade
CRIT_BG = "#2A1420"       # dark red row tint (critical)
HIGH_BG = "#2A2210"       # dark amber row tint (high)
MONO = "Consolas"         # ships with every Windows install

SEVERITY_COLS = ("high", "crit", "med", "low", "info")
SEVERITY_LABELS = {"high": "High", "crit": "Critical", "med": "Medium", "low": "Low", "info": "Info"}
SEVERITY_KEYS = {"high": "High", "crit": "Critical", "med": "Medium", "low": "Low", "info": "Info"}


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Cycode-Stats")
        self.geometry("1180x760")
        self.minsize(1020, 640)
        self.configure(bg=BG)

        self.smap = StudioMap.load()
        names = self.smap.names()
        self.studio_var = tk.StringVar(value=names[0] if names else "")

        self.branch_counts: dict[tuple, object] = {}
        self.repo_rows: dict[str, list] = {}
        self.total_items = 0
        self.fetched_at: str | None = None
        self.bsel: scope.ScopeSelection | None = None
        self.last_report_path: str | None = None

        self.log_q: "queue.Queue[str]" = queue.Queue()
        self._busy = False
        self._fetch_outcome = None
        self._branch_editor = None

        self._apply_style()
        self._build_header()
        self._build_footer()

        self.nb = ttk.Notebook(self)
        self.nb.pack(fill="both", expand=True, padx=10, pady=(0, 6))
        self._build_fetch_tab(self.nb)
        self._build_scope_tab(self.nb)
        self._build_generate_tab(self.nb)

        self._load_studio_data(self.studio_var.get())
        self._refresh_auth_status()
        self.after(150, self._drain_log)

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
        st.configure("TLabel", background=BG, foreground=TEXT, font=base)
        st.configure("Muted.TLabel", background=BG, foreground=MUTED, font=("Segoe UI", 9))
        st.configure("H1.TLabel", background=PRIMARY, foreground=TEXT,
                     font=("Segoe UI Semibold", 15))
        st.configure("Sub.TLabel", background=PRIMARY, foreground=ACCENT,
                     font=(MONO, 9))
        st.configure("Section.TLabel", background=BG, foreground=ACCENT,
                     font=("Segoe UI Semibold", 11))

        st.configure("TButton", font=base, padding=(10, 5), background=CARD,
                     foreground=TEXT, bordercolor=CARD_BORDER, focusthickness=0)
        st.map("TButton", background=[("active", CARD_BORDER)])
        st.configure("Accent.TButton", background=ACCENT, foreground="#03141A",
                     padding=(12, 6), font=("Segoe UI Semibold", 10), borderwidth=0)
        st.map("Accent.TButton", background=[("active", ACCENT_DK), ("disabled", CARD_BORDER)])
        st.configure("Teal.TButton", background=GOOD, foreground="#03170E",
                     padding=(12, 6), font=("Segoe UI Semibold", 10), borderwidth=0)
        st.map("Teal.TButton", background=[("active", "#22B589"), ("disabled", CARD_BORDER)])

        st.configure("TCheckbutton", background=BG, foreground=TEXT, font=base,
                     indicatorbackground=CARD, indicatorforeground=ACCENT,
                     bordercolor=CARD_BORDER, focuscolor=BG)
        st.map("TCheckbutton", background=[("active", BG)],
               indicatorbackground=[("selected", CARD), ("active", CARD_BORDER)],
               foreground=[("active", ACCENT)])

        st.configure("TEntry", fieldbackground=CARD, foreground=TEXT, insertcolor=TEXT,
                     bordercolor=CARD_BORDER, lightcolor=CARD_BORDER, darkcolor=CARD_BORDER)
        st.configure("TCombobox", fieldbackground=CARD, background=CARD, foreground=TEXT,
                     arrowcolor=ACCENT, bordercolor=CARD_BORDER, selectbackground=CARD,
                     selectforeground=TEXT)
        st.map("TCombobox",
               fieldbackground=[("readonly", CARD), ("disabled", CARD)],
               foreground=[("readonly", TEXT)],
               background=[("readonly", CARD)])
        self.option_add("*TCombobox*Listbox.background", CARD)
        self.option_add("*TCombobox*Listbox.foreground", TEXT)
        self.option_add("*TCombobox*Listbox.selectBackground", ACCENT_DK)
        self.option_add("*TCombobox*Listbox.selectForeground", "#03141A")

        st.configure("Treeview", rowheight=24, font=base, background=CARD,
                     fieldbackground=CARD, foreground=TEXT, bordercolor=CARD_BORDER,
                     borderwidth=0)
        st.map("Treeview", background=[("selected", ACCENT_DK)],
               foreground=[("selected", "#03141A")])
        st.configure("Treeview.Heading", font=("Segoe UI Semibold", 9), background=PRIMARY,
                     foreground=ACCENT, bordercolor=PRIMARY, relief="flat")
        st.map("Treeview.Heading", background=[("active", CARD_BORDER)])

        st.configure("TNotebook", background=BG, bordercolor=BG, tabmargins=(4, 6, 4, 0))
        st.configure("TNotebook.Tab", padding=(16, 9), font=("Segoe UI Semibold", 9),
                     background=BG, foreground=MUTED, bordercolor=BG)
        st.map("TNotebook.Tab",
               background=[("selected", CARD)],
               foreground=[("selected", ACCENT)])

        st.configure("Vertical.TScrollbar", background=CARD, troughcolor=BG,
                     bordercolor=BG, arrowcolor=MUTED, relief="flat")
        st.map("Vertical.TScrollbar", background=[("active", CARD_BORDER)])

    def _build_header(self):
        bar = tk.Frame(self, bg=PRIMARY, height=64)
        bar.pack(side="top", fill="x")
        bar.pack_propagate(False)
        tk.Label(bar, text="\U0001F6E1", bg=PRIMARY, fg=ACCENT,
                 font=("Segoe UI", 22)).pack(side="left", padx=(16, 8))
        col = tk.Frame(bar, bg=PRIMARY)
        col.pack(side="left", pady=8)
        tk.Label(col, text="CYCODE-STATS", bg=PRIMARY, fg=TEXT,
                 font=("Segoe UI Semibold", 15)).pack(anchor="w")
        tk.Label(col, text="> studios :: open_violations :: excel", bg=PRIMARY,
                 fg=ACCENT, font=(MONO, 9)).pack(anchor="w")
        tk.Frame(self, bg=ACCENT, height=2).pack(side="top", fill="x")

    def _build_footer(self):
        tk.Frame(self, bg=CARD_BORDER, height=1).pack(side="bottom", fill="x")
        bar = tk.Frame(self, bg=PRIMARY_DK)
        bar.pack(side="bottom", fill="x")
        self.footer = tk.Label(bar, text="", bg=PRIMARY_DK, fg=MUTED,
                               font=(MONO, 8), anchor="w", padx=12, pady=3)
        self.footer.pack(side="left")

    def _update_footer(self):
        studio = self.studio_var.get()
        pid = self.smap.project_id(studio)
        fetched = self.fetched_at or "never"
        self.footer.configure(
            text=f"\U0001F4C1 Data: {config.DATA_DIR}    •    "
                 f"Studio: {studio or '(none)'} (project {pid})    •    "
                 f"Last fetch: {fetched}    •    "
                 f"Repos: {len(self.repo_rows)}    •    Open violations: {self.total_items:,}")

    # ------------------------------------------------------------ data
    def _load_studio_data(self, studio: str):
        cat = scope.load_catalogue(studio) if studio else None
        if cat:
            self.branch_counts = cat["branch_counts"]
            self.total_items = cat["total_items"]
            self.fetched_at = cat["fetched_at"]
        else:
            self.branch_counts = {}
            self.total_items = 0
            self.fetched_at = None

        self.repo_rows = scope.build_repo_rows(self.branch_counts)
        self.bsel = scope.ScopeSelection.load(studio) if studio else None
        if self.bsel:
            self.bsel.sync_with_repo_rows(self.repo_rows)

        if hasattr(self, "fetch_status"):
            self._refresh_fetch_tab_info()
        if hasattr(self, "scope_tree"):
            self._refresh_scope_tree()
        if hasattr(self, "gen_info"):
            self._refresh_generate_tab_info()
        self._update_footer()

    def _on_studio_change(self, *_):
        self._load_studio_data(self.studio_var.get())

    def _studio_picker(self, parent):
        row = ttk.Frame(parent)
        ttk.Label(row, text="Studio:").pack(side="left", padx=(0, 6))
        cb = ttk.Combobox(row, textvariable=self.studio_var, state="readonly",
                          values=self.smap.names(), width=22)
        cb.pack(side="left")
        cb.bind("<<ComboboxSelected>>", self._on_studio_change)
        return row

    def _refresh_studio_choices(self):
        names = self.smap.names()
        for attr in ("fetch_studio_cb", "scope_studio_cb", "gen_studio_cb"):
            if hasattr(self, attr):
                getattr(self, attr)["values"] = names
        if self.studio_var.get() not in names and names:
            self.studio_var.set(names[0])
            self._on_studio_change()

    # ------------------------------------------------------------ Tab 1: Fetch
    def _build_fetch_tab(self, nb):
        f = ttk.Frame(nb, padding=14)
        nb.add(f, text="1. Studios & Fetch")

        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="Pick a studio and fetch its open Cycode violations",
                  style="Section.TLabel").pack(side="left")

        picker = ttk.Frame(top)
        picker.pack(side="right")
        ttk.Label(picker, text="Studio:").pack(side="left", padx=(0, 6))
        self.fetch_studio_cb = ttk.Combobox(picker, textvariable=self.studio_var, state="readonly",
                                            values=self.smap.names(), width=22)
        self.fetch_studio_cb.pack(side="left")
        self.fetch_studio_cb.bind("<<ComboboxSelected>>", self._on_studio_change)
        ttk.Button(picker, text="⚙ Manage Studios", command=self._open_manage_studios).pack(
            side="left", padx=(10, 0))

        card = tk.Frame(f, bg=CARD, highlightbackground=CARD_BORDER, highlightthickness=1)
        card.pack(fill="x", pady=12)
        self.fetch_status = tk.Label(card, text="Idle.", bg=CARD, fg=TEXT, anchor="w",
                                     font=("Segoe UI Semibold", 10), padx=14, pady=10)
        self.fetch_status.pack(fill="x")

        auth_row = tk.Frame(card, bg=CARD)
        auth_row.pack(fill="x", padx=14, pady=(0, 10))
        self.auth_dot = tk.Label(auth_row, text="●", bg=CARD, font=("Segoe UI", 11))
        self.auth_dot.pack(side="left")
        self.auth_label = tk.Label(auth_row, text="", bg=CARD, fg=MUTED,
                                   font=(MONO, 9, "bold"))
        self.auth_label.pack(side="left", padx=(4, 10))
        self.signin_btn = ttk.Button(auth_row, text="\U0001F511 Sign in to Cycode",
                                     command=lambda: self._on_sign_in(then_fetch=False))
        self.signin_btn.pack(side="left")

        btns = ttk.Frame(f)
        btns.pack(fill="x", pady=(0, 8))
        self.fetch_btn = ttk.Button(btns, text="⬇ Fetch violations", style="Accent.TButton",
                                    command=self._on_fetch)
        self.fetch_btn.pack(side="left")
        ttk.Label(btns, text="First time on this machine: click Sign in to Cycode, "
                             "log in through your browser, then Fetch. Nothing else to "
                             "install - it's all bundled in this exe.",
                  style="Muted.TLabel", wraplength=560).pack(side="left", padx=12)

        ttk.Label(f, text="Activity log", style="Section.TLabel").pack(anchor="w", pady=(6, 4))
        log_frame = tk.Frame(f, bg=CARD, highlightbackground=CARD_BORDER, highlightthickness=1)
        log_frame.pack(fill="both", expand=True)
        self.log_text = tk.Text(log_frame, height=16, bg=CARD, fg=TEXT, relief="flat",
                                font=("Consolas", 9), wrap="word", state="disabled")
        sb = ttk.Scrollbar(log_frame, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=sb.set)
        self.log_text.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=8)
        sb.pack(side="right", fill="y")

    def _refresh_fetch_tab_info(self):
        pid = self.smap.project_id(self.studio_var.get())
        if self.total_items:
            self.fetch_status.configure(
                text=f"Last fetch for '{self.studio_var.get()}' (project {pid}): "
                     f"{self.total_items:,} open violations across {len(self.repo_rows)} repos "
                     f"— {self.fetched_at}")
        else:
            self.fetch_status.configure(
                text=f"No data yet for '{self.studio_var.get()}' (project {pid}). Click Fetch.")

    def _refresh_auth_status(self):
        try:
            authed = cycode_cli.is_authenticated()
        except Exception:
            authed = False
        if authed:
            self.auth_dot.configure(fg=GOOD, bg=CARD)
            self.auth_label.configure(text="SIGNED IN · Cycode session active on this machine", fg=GOOD)
            self.signin_btn.configure(text="\U0001F511 Re-sign in")
        else:
            self.auth_dot.configure(fg=BAD, bg=CARD)
            self.auth_label.configure(text="NOT SIGNED IN", fg=BAD)
            self.signin_btn.configure(text="\U0001F511 Sign in to Cycode")
        return authed

    def _append_log(self, msg: str):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", msg + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _drain_log(self):
        try:
            while True:
                msg = self.log_q.get_nowait()
                self._append_log(msg)
        except queue.Empty:
            pass

        if self._fetch_outcome is not None:
            kind, payload = self._fetch_outcome
            self._fetch_outcome = None
            self._busy = False
            self.fetch_btn.configure(state="normal")
            self.signin_btn.configure(state="normal")
            if hasattr(self, "scope_refresh_btn"):
                self.scope_refresh_btn.configure(state="normal")

            if kind == "fetch_ok":
                studio, repo_counts, branch_counts, total_items = payload
                if studio == self.studio_var.get():
                    self.branch_counts = branch_counts
                    self.total_items = total_items
                    self.fetched_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    self.repo_rows = scope.build_repo_rows(self.branch_counts)
                    self.bsel = scope.ScopeSelection.load(studio)
                    self.bsel.sync_with_repo_rows(self.repo_rows)
                    self._refresh_fetch_tab_info()
                    self._refresh_scope_tree()
                    self._refresh_generate_tab_info()
                    self._update_footer()
                self._append_log(f"Done. {total_items:,} open violations fetched for '{studio}'.")
            elif kind == "fetch_err":
                messagebox.showerror("Fetch failed", str(payload))
                self._append_log(f"ERROR: {payload}")
                self._refresh_auth_status()
            elif kind == "auth_ok":
                self._refresh_auth_status()
                self._append_log("Signed in to Cycode.")
                if payload:  # then_fetch was requested
                    self._on_fetch()
            elif kind == "auth_err":
                self._refresh_auth_status()
                messagebox.showerror("Sign-in failed", str(payload))
                self._append_log(f"ERROR: {payload}")

        self.after(150, self._drain_log)

    def _on_fetch(self):
        if self._busy:
            return
        studio = self.studio_var.get()
        pid = self.smap.project_id(studio)
        if not studio or pid is None:
            messagebox.showwarning("No studio", "Add a studio with a project id first "
                                                "(Manage Studios).")
            return
        if not self._refresh_auth_status():
            if messagebox.askyesno(
                "Sign in required",
                "You're not signed in to Cycode on this machine yet.\n\n"
                "Click Yes to open your browser and sign in now (one-time)."
            ):
                self._on_sign_in(then_fetch=True)
            return

        self._busy = True
        self.fetch_btn.configure(state="disabled")
        self.signin_btn.configure(state="disabled")
        if hasattr(self, "scope_refresh_btn"):
            self.scope_refresh_btn.configure(state="disabled")
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")
        self._append_log(f"Fetching open violations for '{studio}' (project {pid})...")
        threading.Thread(target=self._fetch_worker, args=(studio, pid), daemon=True).start()

    def _fetch_worker(self, studio: str, project_id: int):
        try:
            repo_counts, branch_counts, total_items = cycode_cli.collect_counts(
                project_id, progress=self.log_q.put
            )
        except (cycode_cli.CycodeAuthError, cycode_cli.CycodeCliError) as exc:
            self._fetch_outcome = ("fetch_err", str(exc))
            return
        except Exception as exc:  # unexpected - surface it instead of hanging the UI
            self._fetch_outcome = ("fetch_err", f"Unexpected error: {exc}")
            return

        scope.save_catalogue(studio, branch_counts, total_items)
        self._fetch_outcome = ("fetch_ok", (studio, repo_counts, branch_counts, total_items))

    def _on_sign_in(self, then_fetch: bool = False):
        if self._busy:
            return
        self._busy = True
        self.fetch_btn.configure(state="disabled")
        self.signin_btn.configure(state="disabled")
        self._append_log(
            "Opening your browser to sign in to Cycode - complete the login there, "
            "this may take up to a few minutes..."
        )
        threading.Thread(target=self._signin_worker, args=(then_fetch,), daemon=True).start()

    def _signin_worker(self, then_fetch: bool):
        try:
            cycode_cli.run_auth(progress=self.log_q.put)
        except Exception as exc:
            self._fetch_outcome = ("auth_err", str(exc))
            return
        self._fetch_outcome = ("auth_ok", then_fetch)

    # ------------------------------------------------------------ Manage Studios
    def _open_manage_studios(self):
        win = tk.Toplevel(self)
        win.title("Manage Studios")
        win.geometry("460x420")
        win.configure(bg=BG)
        win.transient(self)
        win.grab_set()

        ttk.Label(win, text="Studio → Cycode project id", style="Section.TLabel").pack(
            anchor="w", padx=12, pady=(12, 4))
        ttk.Label(win, text="The project id is the one used in the Cycode dashboard URL / CLI "
                            "(--project-ids).", style="Muted.TLabel", wraplength=420).pack(
            anchor="w", padx=12)

        tree = ttk.Treeview(win, columns=("id",), show="tree headings", height=10)
        tree.heading("#0", text="Studio")
        tree.heading("id", text="Project ID")
        tree.column("#0", width=240, anchor="w")
        tree.column("id", width=140, anchor="center")
        for name in self.smap.names():
            tree.insert("", "end", iid=name, text=name, values=(self.smap.project_id(name),))
        tree.pack(fill="both", expand=True, padx=12, pady=8)

        form = ttk.Frame(win)
        form.pack(fill="x", padx=12, pady=(0, 8))
        ttk.Label(form, text="Name:").grid(row=0, column=0, sticky="w")
        name_var = tk.StringVar()
        ttk.Entry(form, textvariable=name_var, width=22).grid(row=0, column=1, padx=6)
        ttk.Label(form, text="Project ID:").grid(row=0, column=2, sticky="w")
        id_var = tk.StringVar()
        ttk.Entry(form, textvariable=id_var, width=12).grid(row=0, column=3, padx=6)

        def on_select(_=None):
            sel = tree.selection()
            if sel:
                name_var.set(sel[0])
                id_var.set(str(self.smap.project_id(sel[0])))

        tree.bind("<<TreeviewSelect>>", on_select)

        def add_or_update():
            name = name_var.get().strip()
            pid_raw = id_var.get().strip()
            if not name or not pid_raw:
                messagebox.showwarning("Missing info", "Enter both a studio name and a project id.",
                                       parent=win)
                return
            try:
                pid = int(pid_raw)
            except ValueError:
                messagebox.showwarning("Invalid id", "Project id must be a number.", parent=win)
                return
            self.smap.add_or_update(name, pid)
            if tree.exists(name):
                tree.item(name, values=(pid,))
            else:
                tree.insert("", "end", iid=name, text=name, values=(pid,))
            self._refresh_studio_choices()
            self._update_footer()

        def remove_selected():
            sel = tree.selection()
            if not sel:
                return
            name = sel[0]
            if messagebox.askyesno("Remove studio", f"Remove '{name}'?", parent=win):
                self.smap.remove(name)
                tree.delete(name)
                self._refresh_studio_choices()
                self._update_footer()

        btns = ttk.Frame(win)
        btns.pack(fill="x", padx=12, pady=(0, 12))
        ttk.Button(btns, text="Add / Update", style="Accent.TButton",
                  command=add_or_update).pack(side="left")
        ttk.Button(btns, text="Remove selected", command=remove_selected).pack(side="left", padx=8)
        ttk.Button(btns, text="Close", command=win.destroy).pack(side="right")

    # ------------------------------------------------------------ Tab 2: Scope
    def _build_scope_tab(self, nb):
        f = ttk.Frame(nb, padding=14)
        nb.add(f, text="2. Scope (Repositories & Branches)")

        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="Pick one branch per repository, then Refresh to see its violations",
                  style="Section.TLabel").pack(side="left")

        ttk.Button(top, text="\U0001F4BE Save scope", command=self._save_scope).pack(
            side="right")
        self.scope_refresh_btn = ttk.Button(top, text="\U0001F504 Refresh stats", style="Teal.TButton",
                                            command=self._on_fetch)
        self.scope_refresh_btn.pack(side="right", padx=6)
        ttk.Label(top, text="Studio:").pack(side="right", padx=(0, 4))
        self.scope_studio_cb = ttk.Combobox(top, textvariable=self.studio_var, state="readonly",
                                            values=self.smap.names(), width=18)
        self.scope_studio_cb.pack(side="right", padx=(0, 8))
        self.scope_studio_cb.bind("<<ComboboxSelected>>", self._on_studio_change)

        search_row = ttk.Frame(f)
        search_row.pack(fill="x", pady=(8, 0))
        ttk.Label(search_row, text="\U0001F50D").pack(side="left")
        self.scope_search_var = tk.StringVar(value="")
        entry = ttk.Entry(search_row, textvariable=self.scope_search_var, width=40)
        entry.pack(side="left", padx=6)
        self.scope_search_var.trace_add("write", lambda *_: self._refresh_scope_tree())
        ttk.Button(search_row, text="✕", width=3,
                  command=lambda: self.scope_search_var.set("")).pack(side="left")
        ttk.Label(search_row, text="type any part of a repository name",
                  style="Muted.TLabel").pack(side="left", padx=8)
        self.scope_count = ttk.Label(search_row, text="", style="Muted.TLabel")
        self.scope_count.pack(side="right")

        cols = ("branch", "inc") + SEVERITY_COLS
        self.scope_tree = ttk.Treeview(f, columns=cols, show="tree headings", height=16)
        self.scope_tree.heading("#0", text="Repository")
        self.scope_tree.heading("branch", text="Branch  ▾")
        self.scope_tree.heading("inc", text="Include")
        for c in SEVERITY_COLS:
            self.scope_tree.heading(c, text=SEVERITY_LABELS[c])
        self.scope_tree.column("#0", width=360, anchor="w")
        self.scope_tree.column("branch", width=220, anchor="w")
        self.scope_tree.column("inc", width=64, anchor="center")
        for c in SEVERITY_COLS:
            self.scope_tree.column(c, width=64, anchor="center")
        self.scope_tree.tag_configure("odd", background=STRIPE)
        self.scope_tree.tag_configure("crit", background=CRIT_BG)
        self.scope_tree.tag_configure("high", background=HIGH_BG)
        self.scope_tree.pack(fill="both", expand=True, pady=8)
        self.scope_tree.bind("<Button-1>", self._on_scope_click)
        self.scope_tree.bind("<MouseWheel>", lambda e: self._close_branch_editor())

        self.scope_status = ttk.Label(
            f, text="Click Branch to pick a branch. Click Include to toggle whether the repo "
                    "goes into the report.", style="Muted.TLabel")
        self.scope_status.pack(anchor="w")

    def _matches(self, text: str, query: str) -> bool:
        return query.strip().lower() in text.lower() if query else True

    def _refresh_scope_tree(self):
        if not hasattr(self, "scope_tree"):
            return
        self._close_branch_editor()
        self.scope_tree.delete(*self.scope_tree.get_children())

        if not self.repo_rows:
            self.scope_tree.insert("", "end", text="(fetch violations first — tab 1)")
            if hasattr(self, "scope_count"):
                self.scope_count.configure(text="")
            return

        query = self.scope_search_var.get() if hasattr(self, "scope_search_var") else ""
        shown = 0
        for i, repo in enumerate(sorted(self.repo_rows)):
            if not self._matches(repo, query):
                continue
            shown += 1
            branches = self.repo_rows[repo]
            default_branch = branches[0][0] if branches else ""
            branch, include = self.bsel.get(repo, default_branch) if self.bsel else (default_branch, True)
            counts = dict(next((c for b, c in branches if b == branch), {}))

            inc_display = CHECK if include else UNCHECK
            branch_display = f"{branch}   ▾ ({len(branches)})" if len(branches) > 1 else branch
            vals = [branch_display, inc_display] + [counts.get(SEVERITY_KEYS[c], 0) for c in SEVERITY_COLS]

            tags = ["odd"] if i % 2 else []
            if counts.get("Critical", 0):
                tags = ["crit"]
            elif counts.get("High", 0):
                tags = ["high"]
            self.scope_tree.insert("", "end", iid=repo, text=repo, values=vals, tags=tags)

        if hasattr(self, "scope_count"):
            self.scope_count.configure(text=f"{shown} shown / {len(self.repo_rows)} total")

    def _on_scope_click(self, event):
        self._close_branch_editor()
        if self.scope_tree.identify("region", event.x, event.y) != "cell":
            return
        col = self.scope_tree.identify_column(event.x)
        iid = self.scope_tree.identify_row(event.y)
        if not iid or iid not in self.repo_rows:
            return
        if col == "#1":            # Branch column -> dropdown editor
            self._edit_branch(iid)
        elif col == "#2":          # Include column -> toggle
            branches = self.repo_rows[iid]
            default_branch = branches[0][0] if branches else ""
            branch, include = self.bsel.get(iid, default_branch)
            self.bsel.set(iid, branch, not include)
            self._refresh_scope_tree()

    def _close_branch_editor(self):
        if self._branch_editor is not None:
            try:
                self._branch_editor.destroy()
            except tk.TclError:
                pass
            self._branch_editor = None

    def _edit_branch(self, repo: str):
        branches = self.repo_rows.get(repo, [])
        if len(branches) <= 1:
            return
        self._close_branch_editor()
        bbox = self.scope_tree.bbox(repo, "branch")
        if not bbox:
            return
        x, y, w, h = bbox
        names = [b for b, _ in branches]
        current_branch, current_include = self.bsel.get(repo, names[0])
        var = tk.StringVar(value=current_branch)
        cb = ttk.Combobox(self.scope_tree, textvariable=var, values=names, state="readonly")
        cb.place(x=x, y=y, width=max(w, 220), height=h)
        cb.focus_set()
        cb.event_generate("<Button-1>")

        def commit(_=None):
            val = var.get()
            if val:
                self.bsel.set(repo, val, current_include)
                self._refresh_scope_tree()
            self._close_branch_editor()

        # No <FocusOut> handler on purpose: opening the popup list steals focus
        # and would destroy the editor instantly. It closes on selection, Escape,
        # or the next click/scroll in the table.
        cb.bind("<<ComboboxSelected>>", commit)
        cb.bind("<Escape>", lambda e: self._close_branch_editor())
        self._branch_editor = cb

    def _save_scope(self):
        if not self.bsel:
            return
        self.bsel.save()
        messagebox.showinfo("Scope saved", f"Scope saved for '{self.studio_var.get()}'.")

    # ------------------------------------------------------------ Tab 3: Generate
    def _build_generate_tab(self, nb):
        f = ttk.Frame(nb, padding=14)
        nb.add(f, text="3. Generate Report")

        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="Build the Excel report(s)",
                  style="Section.TLabel").pack(side="left")
        ttk.Label(top, text="Studio:").pack(side="right", padx=(0, 4))
        self.gen_studio_cb = ttk.Combobox(top, textvariable=self.studio_var, state="readonly",
                                          values=self.smap.names(), width=18)
        self.gen_studio_cb.pack(side="right")
        self.gen_studio_cb.bind("<<ComboboxSelected>>", self._on_studio_change)

        card = tk.Frame(f, bg=CARD, highlightbackground=CARD_BORDER, highlightthickness=1)
        card.pack(fill="x", pady=12)
        self.gen_info = tk.Label(card, text="", bg=CARD, fg=TEXT, anchor="w", justify="left",
                                 font=("Segoe UI", 10), padx=14, pady=10)
        self.gen_info.pack(fill="x")

        ttk.Label(f, text="Which report(s) to generate", style="Section.TLabel").pack(
            anchor="w", pady=(0, 4))
        self.gen_scoped_var = tk.BooleanVar(value=True)
        self.gen_all_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            f, variable=self.gen_scoped_var,
            text="Scoped report — only repos ticked Include on the Scope tab, each at its "
                 "chosen branch (1 sheet: Scoped Report)").pack(anchor="w", pady=2)
        ttk.Checkbutton(
            f, variable=self.gen_all_var,
            text="All repos & all branches report — everything fetched, ignores Scope "
                 "(2 sheets: Repository Summary, Branch Summary)").pack(anchor="w", pady=2)

        btns = ttk.Frame(f)
        btns.pack(fill="x", pady=12)
        ttk.Button(btns, text="\U0001F4C4 Generate Excel", style="Accent.TButton",
                  command=self._on_generate).pack(side="left")
        self.open_report_btn = ttk.Button(btns, text="Open last report", state="disabled",
                                          command=self._open_last_report)
        self.open_report_btn.pack(side="left", padx=8)
        ttk.Button(btns, text="Open output folder",
                  command=self._open_output_folder).pack(side="left")

        self.gen_status = ttk.Label(f, text="", style="Muted.TLabel", wraplength=900,
                                    justify="left")
        self.gen_status.pack(anchor="w", pady=(6, 0))

    def _refresh_generate_tab_info(self):
        if not hasattr(self, "gen_info"):
            return
        studio = self.studio_var.get()
        pid = self.smap.project_id(studio)
        scoped = sum(1 for _repo, (_b, inc) in (self.bsel.rows.items() if self.bsel else []) if inc)
        self.gen_info.configure(
            text=f"Studio: {studio}   |   Project ID: {pid}\n"
                 f"Last fetch: {self.fetched_at or 'never'}   |   "
                 f"Open violations fetched: {self.total_items:,}\n"
                 f"Repositories in scope: {scoped} of {len(self.repo_rows)}"
        )

    def _on_generate(self):
        studio = self.studio_var.get()
        pid = self.smap.project_id(studio)
        if not studio or pid is None:
            messagebox.showwarning("No studio", "Pick a studio first.")
            return
        if not self.branch_counts:
            messagebox.showwarning("No data", "Fetch violations for this studio first (tab 1).")
            return
        want_scoped = self.gen_scoped_var.get()
        want_all = self.gen_all_var.get()
        if not want_scoped and not want_all:
            messagebox.showwarning("Nothing selected", "Tick at least one report to generate.")
            return
        if want_scoped and (not self.bsel or not any(inc for _b, inc in self.bsel.rows.values())):
            if not messagebox.askyesno(
                "Nothing in scope",
                "No repositories are included in scope, so the scoped report would be empty.\n"
                "Generate it anyway?"
            ):
                want_scoped = False
                if not want_all:
                    return

        date_tag = datetime.now().strftime("%Y-%m-%d")
        safe_studio = "".join(c if c.isalnum() or c in "-_" else "_" for c in studio)
        made: list[str] = []

        try:
            if want_scoped:
                path = config.OUTPUT_DIR / f"{safe_studio}_CycodeReport_Scoped_{date_tag}.xlsx"
                n = report.build_scoped_workbook(studio, pid, self.branch_counts, self.bsel, path)
                made.append(f"Scoped ({n} repos): {path}")
                self.last_report_path = str(path)
            if want_all:
                path = config.OUTPUT_DIR / f"{safe_studio}_CycodeReport_All_{date_tag}.xlsx"
                nr, nb_ = report.build_all_workbook(
                    studio, pid, self.branch_counts, self.total_items, path)
                made.append(f"All ({nr} repos, {nb_} branch rows): {path}")
                self.last_report_path = str(path)
        except PermissionError:
            messagebox.showerror(
                "Report failed",
                "Couldn't write the file - is it open in Excel? Close it and try again.")
            return
        except Exception as exc:
            messagebox.showerror("Report failed", str(exc))
            return

        self.open_report_btn.configure(state="normal")
        self.gen_status.configure(text="Generated:\n" + "\n".join(made))
        messagebox.showinfo("Report generated", "\n\n".join(made))

    def _open_last_report(self):
        if self.last_report_path and os.path.exists(self.last_report_path):
            os.startfile(self.last_report_path)

    def _open_output_folder(self):
        config.ensure_dirs()
        os.startfile(config.OUTPUT_DIR)


def run():
    app = App()
    app.mainloop()
