"""
In-process integration with the `cycode` Python package (bundled into this
app - not an external CLI on PATH). We invoke the same Click commands the
real `cycode` CLI exposes, in this process, via Click's CliRunner - so the
built exe never depends on anything being pre-installed on the machine it
runs on.

Auth is still "one-time per machine": `cycode`'s own CredentialsManager
reads/writes `~/.cycode/credentials.yaml`, so once a user signs in (via our
Sign In button, which drives the same browser login as `cycode auth`), it
persists for next time, same as if they'd run the real CLI.
"""
from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from typing import Callable, Optional

from . import config

ANSI_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

ProgressFn = Optional[Callable[[str], None]]

_click_command = None  # lazy singleton - see _get_click_command()


class CycodeAuthError(RuntimeError):
    """Raised when Cycode reports the user isn't authenticated."""


class CycodeCliError(RuntimeError):
    """Raised for any other Cycode/parsing failure."""


def is_authenticated() -> bool:
    """Cheap, no-network check: is there a stored client id/secret?"""
    from cycode.cli.user_settings.credentials_manager import CredentialsManager

    client_id, client_secret = CredentialsManager().get_credentials()
    return bool(client_id and client_secret)


def run_auth(progress: ProgressFn = None) -> None:
    """Drive the same interactive browser login as `cycode auth`.

    Opens the user's browser, waits (up to ~3 minutes) for them to
    complete login, then saves credentials to ~/.cycode/credentials.yaml.
    Safe to call from a worker thread; raises on failure/timeout.
    """
    from cycode.cli.apps.auth.auth_manager import AuthManager

    if progress:
        progress("Opening your browser to sign in to Cycode...")
    try:
        AuthManager().authenticate()
    except Exception as exc:
        raise CycodeAuthError(f"Cycode sign-in failed: {exc}") from exc
    if progress:
        progress("Signed in to Cycode.")


def _get_click_command():
    """Build the cycode Click command tree once, lazily.

    Important: this must only be called AFTER is_authenticated() is True.
    Cycode builds its `platform` command group from a live OpenAPI spec
    fetched using the stored credentials the first time this is imported;
    importing it while unauthenticated permanently caches an empty group
    for the life of this process.
    """
    global _click_command
    if _click_command is None:
        import typer

        from cycode.cli.app import app as cycode_typer_app

        _click_command = typer.main.get_command(cycode_typer_app)
    return _click_command


def extract_json(text: str) -> dict:
    """Extract the Cycode JSON object even if warning/log text surrounds it."""
    cleaned = ANSI_RE.sub("", text or "")
    decoder = json.JSONDecoder()

    for match in re.finditer(r"[\{\[]", cleaned):
        try:
            obj, _ = decoder.raw_decode(cleaned[match.start():])
        except json.JSONDecodeError:
            continue

        if isinstance(obj, dict) and (
            "items" in obj or "next_page_token" in obj or "page_size" in obj
        ):
            return obj

    raise CycodeCliError("Could not find a valid Cycode JSON response in the output.")


def run_cycode_json(project_id, next_page_token=None, retries=2, status=config.STATUS):
    if not is_authenticated():
        raise CycodeAuthError("Not signed in to Cycode yet.")

    from click.testing import CliRunner

    args = [
        "--output", "json",
        "platform", "violations", "list",
        "--status", status,
        "--project-ids", str(project_id),
        "--page-size", str(config.PAGE_SIZE),
    ]
    if next_page_token:
        args += ["--next-page-token", next_page_token]

    cmd = _get_click_command()
    runner = CliRunner()

    last_error = None
    for attempt in range(1, retries + 1):
        result = runner.invoke(cmd, args, catch_exceptions=True)
        output = result.output or ""

        if result.exit_code == 0:
            try:
                return extract_json(output)
            except Exception as exc:
                last_error = exc
        else:
            low = output.lower()
            if (
                "credentials not found" in low
                or "cycode auth" in low
                or "no such command 'violations'" in low
                or "unauthorized" in low
            ):
                raise CycodeAuthError(
                    "Cycode reported you're not signed in (or the session expired). "
                    "Use Sign In again, then retry."
                )
            last_error = CycodeCliError(
                str(result.exception) if result.exception else output.strip() or "Unknown Cycode CLI error"
            )

    raise CycodeCliError(f"Cycode request failed after {retries} attempts: {last_error}")


def find_first_key(obj, wanted_key):
    """Fallback search for a key anywhere in a nested JSON object."""
    if isinstance(obj, dict):
        if wanted_key in obj and obj[wanted_key] not in (None, ""):
            return obj[wanted_key]
        for value in obj.values():
            found = find_first_key(value, wanted_key)
            if found not in (None, ""):
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = find_first_key(value, wanted_key)
            if found not in (None, ""):
                return found
    return None


def normalize_repository_name(repo):
    if not repo:
        return "(No repository)"
    value = str(repo).strip()
    return config.REPOSITORY_ALIASES.get(value.casefold(), value)


def get_repo_and_branch(item):
    details = item.get("detection_details")
    repo = None
    branch = None

    if isinstance(details, dict):
        repo = details.get("repository_name")
        branch = details.get("branch_name")
    elif isinstance(details, list):
        for detail in details:
            if not isinstance(detail, dict):
                continue
            repo = repo or detail.get("repository_name")
            branch = branch or detail.get("branch_name")
            if repo and branch:
                break

    repo = repo or find_first_key(item, "repository_name")
    branch = branch or find_first_key(item, "branch_name")

    repo = normalize_repository_name(repo)
    branch = str(branch).strip() if branch else "(No branch)"
    return repo, branch


def normalize_severity(item):
    value = item.get("severity") or item.get("risk_score_severity")
    if value is None:
        value = find_first_key(item, "severity")
    if value is None:
        raise CycodeCliError(f"Severity is missing for violation {item.get('id', '<unknown>')}")

    normalized = str(value).strip().title()
    allowed = {s.lower(): s for s in config.SEVERITIES}
    if normalized.lower() not in allowed:
        raise CycodeCliError(
            f"Unexpected severity '{value}' for violation {item.get('id', '<unknown>')}"
        )
    return allowed[normalized.lower()]


def collect_counts(project_id, status=config.STATUS, progress: ProgressFn = None):
    """Fetch every open violation for a project id and aggregate by repo/branch.

    Returns (repo_counts, branch_counts, total_items) where:
      repo_counts[repo] = Counter(severity -> count)
      branch_counts[(repo, branch)] = Counter(severity -> count)
    """
    repo_counts: dict[str, Counter] = defaultdict(Counter)
    branch_counts: dict[tuple, Counter] = defaultdict(Counter)
    seen_ids = set()

    token = None
    page_no = 0
    total_items = 0
    duplicate_items = 0
    # Diagnostic: totals for EVERY severity-like field Cycode returns, so we can
    # tell which one matches the dashboard.
    field_totals: dict[str, Counter] = defaultdict(Counter)
    logged_keys = False

    while True:
        page_no += 1
        data = run_cycode_json(project_id, token, status=status)
        items = data.get("items") or []

        if not isinstance(items, list):
            raise CycodeCliError("Cycode response field 'items' is not a list.")

        added_this_page = 0
        for item in items:
            if not isinstance(item, dict):
                continue

            violation_id = item.get("id")
            if violation_id:
                if violation_id in seen_ids:
                    duplicate_items += 1
                    continue
                seen_ids.add(violation_id)

            if progress and not logged_keys:
                progress("Fields Cycode returns per violation: " + ", ".join(sorted(item.keys())))
                logged_keys = True
            for key, val in item.items():
                if "severity" in str(key).lower() and isinstance(val, str):
                    field_totals[key][val.strip().title()] += 1

            repo, branch = get_repo_and_branch(item)
            severity = normalize_severity(item)

            repo_counts[repo][severity] += 1
            branch_counts[(repo, branch)][severity] += 1
            total_items += 1
            added_this_page += 1

        if progress:
            progress(
                f"Page {page_no}: received {len(items):,}, "
                f"added {added_this_page:,}, total {total_items:,}"
            )

        token = data.get("next_page_token")
        if not token:
            break

    if duplicate_items and progress:
        progress(f"Skipped {duplicate_items:,} duplicate violation IDs.")

    if progress:
        used = "'severity' (falls back to 'risk_score_severity')"
        progress(f"--- Whole-project totals ({total_items:,} violations). Report uses: {used} ---")
        for key, counter in sorted(field_totals.items()):
            parts = " | ".join(f"{s}: {counter.get(s, 0):,}" for s in config.SEVERITIES)
            progress(f"  by '{key}':  {parts}")
        progress("Compare a line above with the Cycode dashboard (Open violations).")

    return repo_counts, branch_counts, total_items
