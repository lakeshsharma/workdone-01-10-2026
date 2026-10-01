"""
Outlook integration via COM (pywin32).

Default behaviour is to *open a draft* for the user to review and send — this is
safer than firing mail automatically. Set display=False to send directly.
"""
from __future__ import annotations

import os

from . import config


def send_report(to: str, cc: str, subject: str, html_body: str,
                attachments: list[str], display: bool = True) -> str:
    try:
        import win32com.client  # type: ignore
    except ImportError:
        return ("pywin32 is not installed. Run:  pip install pywin32\n"
                "(or use the packaged .exe which bundles it).")

    try:
        outlook = win32com.client.Dispatch("Outlook.Application")
    except Exception as e:  # noqa: BLE001
        return f"Could not start Outlook: {e}"

    mail = outlook.CreateItem(0)  # 0 = olMailItem
    mail.To = to or ""
    mail.CC = cc or ""
    mail.Subject = subject
    mail.HTMLBody = html_body
    for a in attachments:
        if a and os.path.exists(a):
            mail.Attachments.Add(os.path.abspath(a))

    if display:
        mail.Display(False)      # open the draft, do NOT send
        return "Draft opened in Outlook — review and click Send."
    mail.Send()
    return "Email sent via Outlook."


def default_message(studio: str, period: str) -> str:
    """Editable plain-text intro shown in the Preview & Edit dialog."""
    return (f"Hi team,\n\n"
            f"Please find attached the SonarQube vulnerability report for "
            f"{studio} ({period}).")


def build_html_body(studio: str, period: str, totals: dict[str, int],
                    project_count: int, message: str | None = None) -> str:
    """Compose the HTML body. `message` (plain text, user-editable) becomes the
    intro; the stats table + footer are appended automatically."""
    from html import escape
    text = message if message is not None else default_message(studio, period)
    intro = "".join(
        (f"<p style='margin:0 0 10px'>{escape(line)}</p>" if line.strip() else "<div style='height:6px'></div>")
        for line in text.split("\n"))
    return f"""
    <div style="font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#20232A">
    {intro}
    <table border="1" cellpadding="6" cellspacing="0"
           style="border-collapse:collapse;margin:6px 0">
      <tr style="background:#DDEBF7">
        <th>Critical</th><th>High</th><th>Medium</th><th>Low</th><th>Total (C+H)</th>
      </tr>
      <tr align="center">
        <td>{totals.get('Critical',0)}</td>
        <td>{totals.get('High',0)}</td>
        <td>{totals.get('Medium',0)}</td>
        <td>{totals.get('Low',0)}</td>
        <td><b>{totals.get('Critical',0)+totals.get('High',0)}</b></td>
      </tr>
    </table>
    <p style="margin:6px 0">Projects covered: {project_count}.</p>
    <p style="margin:6px 0">Regards,<br>{escape(config.APP_NAME)}</p>
    </div>
    """
