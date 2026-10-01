"""Excel report generation for a single studio.

Two independent reports can be produced:
- Scoped report: only the repos ticked Include on the Scope tab, each at the
  single branch chosen there.
- All report: every repo and every branch last fetched (repo-wise complete
  totals + branch-wise detail), ignoring Scope.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime
from pathlib import Path

from . import config

SEVERITY_HEADERS = ["High", "Critical", "Medium", "Low", "Info"]


def _require_openpyxl():
    try:
        import openpyxl  # noqa: F401
    except ModuleNotFoundError:
        raise SystemExit(
            "openpyxl is required to create Excel. Install it once with:\n"
            "  py -m pip install openpyxl"
        )


def _subtitle(studio: str, project_id: int) -> str:
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"Studio: {studio} | Project ID: {project_id} | Status: {config.STATUS} | Generated: {generated}"


def _write_sheet(ws, title, subtitle, key_headers, rows, key_widths):
    """rows: list of (key_tuple, Counter). Writes header, data, formulas, totals."""
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    title_fill = PatternFill("solid", fgColor="17365D")
    header_fill = PatternFill("solid", fgColor="D9EAF7")
    total_fill = PatternFill("solid", fgColor="E2F0D9")
    formula_fill = PatternFill("solid", fgColor="F2F2F2")
    thin_blue = Side(style="thin", color="5B9BD5")
    total_border = Border(top=Side(style="thin", color="7F7F7F"))

    nkeys = len(key_headers)
    headers = key_headers + SEVERITY_HEADERS + ["C+H+M+L", "C+H+M+L+Info"]
    ncols = len(headers)
    first_sev = nkeys + 1                      # High
    last_chml = nkeys + 4                      # Low  (High..Low = C+H+M+L)
    last_info = nkeys + 5                      # Info
    L = get_column_letter

    ws.sheet_view.showGridLines = False
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
    cell = ws.cell(1, 1, title)
    cell.fill = title_fill
    cell.font = Font(color="FFFFFF", bold=True, size=14)
    cell.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 26

    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=ncols)
    ws.cell(2, 1, subtitle).font = Font(color="666666")

    for col, header in enumerate(headers, 1):
        c = ws.cell(4, col, header)
        c.fill = header_fill
        c.font = Font(bold=True, color="1F1F1F")
        c.alignment = Alignment(horizontal="center", vertical="center")
        c.border = Border(bottom=thin_blue)
    ws.freeze_panes = "A5"

    start_row = 5
    for idx, (keys, counts) in enumerate(rows, start_row):
        for i, k in enumerate(keys, 1):
            ws.cell(idx, i, k).font = Font(color="008000")
        for j, sev in enumerate(SEVERITY_HEADERS):
            ws.cell(idx, first_sev + j, counts.get(sev, 0)).font = Font(color="008000")
        ws.cell(idx, last_info + 1, f"=SUM({L(first_sev)}{idx}:{L(last_chml)}{idx})")
        ws.cell(idx, last_info + 2, f"=SUM({L(first_sev)}{idx}:{L(last_info)}{idx})")
        for col in (last_info + 1, last_info + 2):
            ws.cell(idx, col).font = Font(color="000000")
            ws.cell(idx, col).fill = formula_fill

    last_data_row = start_row + len(rows) - 1
    total_row = last_data_row + 1
    ws.cell(total_row, 1, "TOTAL").font = Font(bold=True)
    for col in range(first_sev, ncols + 1):
        if rows:
            ws.cell(total_row, col, f"=SUM({L(col)}{start_row}:{L(col)}{last_data_row})")
        else:
            ws.cell(total_row, col, 0)
        ws.cell(total_row, col).font = Font(bold=True)
    for col in range(1, ncols + 1):
        ws.cell(total_row, col).fill = total_fill
        ws.cell(total_row, col).border = total_border

    ws.auto_filter.ref = f"A4:{L(ncols)}{max(last_data_row, start_row)}"
    for i, w in enumerate(key_widths, 1):
        ws.column_dimensions[L(i)].width = w
    for col in range(first_sev, ncols + 1):
        ws.column_dimensions[L(col)].width = 14
    for row in ws.iter_rows(min_row=start_row, max_row=total_row, min_col=first_sev, max_col=ncols):
        for c in row:
            c.number_format = "#,##0"
            c.alignment = Alignment(horizontal="right")


def _new_workbook():
    from openpyxl import Workbook

    wb = Workbook()
    try:
        wb.calculation.fullCalcOnLoad = True
        wb.calculation.forceFullCalc = True
        wb.calculation.calcMode = "auto"
    except Exception:
        pass
    return wb


def build_scoped_workbook(studio, project_id, branch_counts, scope_selection, output_path: Path) -> int:
    """One sheet: each Included repo at its chosen branch. Returns rows written."""
    _require_openpyxl()
    wb = _new_workbook()
    ws = wb.active
    ws.title = "Scoped Report"

    rows = []
    for repo, (branch, include) in scope_selection.rows.items():
        if not include:
            continue
        counts = branch_counts.get((repo, branch))
        if counts is None:
            continue
        rows.append(((repo, branch), counts))
    rows.sort(key=lambda r: (-sum(r[1].values()), r[0][0].lower()))

    subtitle = _subtitle(studio, project_id) + f" | Scoped repos: {len(rows):,}"
    _write_sheet(ws, f"{studio} - Cycode Open Violations (Scoped)", subtitle,
                 ["Repository", "Branch"], rows, [42, 34])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(output_path)
    return len(rows)


def build_all_workbook(studio, project_id, branch_counts, total_items, output_path: Path) -> tuple[int, int]:
    """Two sheets covering everything fetched, ignoring Scope:
    - Repository Summary: every repo, all branches summed (incl. unbranched).
    - Branch Summary: every repo+branch combo.
    Returns (repo_rows, branch_rows).
    """
    _require_openpyxl()
    wb = _new_workbook()
    ws = wb.active
    ws.title = "Repository Summary"
    bs = wb.create_sheet("Branch Summary")
    subtitle = _subtitle(studio, project_id)

    repo_totals: dict[str, Counter] = {}
    for (repo, _branch), counts in branch_counts.items():
        repo_totals.setdefault(repo, Counter()).update(counts)
    repo_rows = sorted(
        (((repo,), c) for repo, c in repo_totals.items()),
        key=lambda r: (-sum(r[1].values()), r[0][0].lower()),
    )
    _write_sheet(ws, f"{studio} - Cycode Open Violations (All Repositories)",
                 subtitle + f" | Repos: {len(repo_rows):,} | Total violations: {total_items:,}",
                 ["Repository"], repo_rows, [42])

    named = {k: v for k, v in branch_counts.items() if k[1] != "(No branch)"}
    no_branch = sum(sum(c.values()) for (_r, b), c in branch_counts.items() if b == "(No branch)")
    branch_rows = [
        ((repo, branch), counts)
        for (repo, branch), counts in sorted(
            named.items(),
            key=lambda x: (x[0][0].lower(), -sum(x[1].values()), x[0][1].lower()),
        )
    ]
    _write_sheet(bs, f"{studio} - Cycode Open Violations (All Branches)",
                 subtitle + f" | Repo/branch rows: {len(branch_rows):,}"
                 f" | No-branch violations excluded: {no_branch:,}",
                 ["Repository", "Branch"], branch_rows, [42, 34])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(output_path)
    return len(repo_rows), len(branch_rows)
