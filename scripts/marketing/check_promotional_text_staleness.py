#!/usr/bin/env python3
"""Check whether the en-CA promotional text needs a monthly refresh.

The freshness timer is keyed to the companion *_refreshed_at.txt file, which
records the date the copy was last submitted to App Store Connect (not the date
of the last git commit touching the file). Update that file whenever you submit
a new promotional text through App Store Connect / Fastlane deliver.

Usage examples:
  # Check freshness (human-readable):
  python3 scripts/marketing/check_promotional_text_staleness.py

  # Check and auto-create a Linear issue when stale (run from monthly report):
  python3 scripts/marketing/check_promotional_text_staleness.py --create-linear-issue

  # Deterministic date override for tests:
  python3 scripts/marketing/check_promotional_text_staleness.py --today 2026-05-07
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date, timedelta
import json
import os
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen
from urllib.error import URLError

DEFAULT_PROMOTIONAL_TEXT_PATH = Path("ios/fastlane/metadata/en-CA/promotional_text.txt")
MAX_AGE_DAYS = 30
STALE_PATTERNS = {
    "hard-coded Parliament number": re.compile(r"\b\d{1,2}(?:st|nd|rd|th) Parliament\b", re.IGNORECASE),
    "uses 'free'": re.compile(r"\bfree\b", re.IGNORECASE),
}
SITTING_CLAIM_PATTERN = re.compile(r"\bsitting\b", re.IGNORECASE)

LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
LINEAR_EPAC_TEAM_KEY = "EPAC"
SITTING_CALENDAR_URL_TEMPLATE = "https://www.ourcommons.ca/en/sitting-calendar/{year}"


@dataclass(frozen=True)
class FreshnessReport:
    path: Path
    text: str
    last_refreshed_at: date
    age_days: int
    warnings: list[str]
    is_sitting_confirmed: bool | None = None

    @property
    def is_stale(self) -> bool:
        return self.age_days > MAX_AGE_DAYS or bool(self.warnings)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--path",
        type=Path,
        default=DEFAULT_PROMOTIONAL_TEXT_PATH,
        help="Promotional text file to inspect",
    )
    parser.add_argument(
        "--today",
        type=date.fromisoformat,
        default=date.today(),
        help="Override today's date (YYYY-MM-DD) for deterministic checks",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format",
    )
    parser.add_argument(
        "--fail-on-stale",
        action="store_true",
        help="Exit non-zero when the promotional text should be refreshed",
    )
    parser.add_argument(
        "--create-linear-issue",
        action="store_true",
        help=(
            "When stale, create a Linear ASO refresh task via the Linear API. "
            "Requires LINEAR_API_KEY env var."
        ),
    )
    parser.add_argument(
        "--skip-calendar-check",
        action="store_true",
        help="Do not fetch the sitting calendar from ourcommons.ca",
    )
    return parser.parse_args()


def refreshed_at_path(promotional_text_path: Path) -> Path:
    """Return the companion date-file path for the given promotional text file."""
    stem = promotional_text_path.stem  # e.g. "promotional_text"
    return promotional_text_path.parent / f"{stem}_refreshed_at.txt"


def last_refresh_date(path: Path) -> date:
    """Read the last App Store submission date from the companion *_refreshed_at.txt file.

    This file is manually updated whenever the promotional text is submitted to
    App Store Connect. It is intentionally separate from git history so that
    unrelated file touches (rebases, reformatting) do not reset the staleness clock.
    """
    date_file = refreshed_at_path(path)
    if not date_file.exists():
        raise FileNotFoundError(
            f"Companion date file not found: {date_file}\n"
            "Create it with the date the promotional text was last submitted to App Store Connect "
            "(YYYY-MM-DD, one line)."
        )
    raw = date_file.read_text(encoding="utf-8").strip()
    try:
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise ValueError(f"{date_file} must contain a YYYY-MM-DD date; got: {raw!r}") from exc


def fetch_sitting_days(year: int) -> set[str]:
    """Fetch the annual sitting calendar and return a set of ISO date strings for sitting days."""
    url = SITTING_CALENDAR_URL_TEMPLATE.format(year=year)
    try:
        req = Request(url, headers={"User-Agent": "epac-staleness-checker/1.0"})
        with urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8")
        
        # Regex matches dates in class attributes that also contain 'chamber-meeting'.
        # Example: <div class="2026-05-08 ... chamber-meeting ...">
        pattern = re.compile(
            r'class=["\'][^"\']*\b(\d{4}-\d{2}-\d{2})\b[^"\']*\bchamber-meeting\b',
            re.IGNORECASE | re.DOTALL
        )
        return set(pattern.findall(html))
    except (URLError, Exception) as exc:
        print(f"Warning: Could not fetch sitting calendar from {url}: {exc}", file=sys.stderr)
        return set()


def check_sitting_claim(text: str, today: date, sitting_days: set[str]) -> str | None:
    """Verify 'sitting' claims against the calendar. Returns a warning string if stale."""
    if not SITTING_CLAIM_PATTERN.search(text):
        return None
    
    # If we couldn't fetch the calendar, we can't confirm/deny.
    if not sitting_days:
        return None

    # We allow a +/- 3 day window to account for weekends and short adjournments
    # while the promotional text remains 'close enough' to being true.
    for i in range(-3, 4):
        check_date = today + timedelta(days=i)
        if check_date.isoformat() in sitting_days:
            return None

    return "claims Parliament is sitting, but no chamber meetings found within +/- 3 days"


def warning_labels(text: str) -> list[str]:
    return [label for label, pattern in STALE_PATTERNS.items() if pattern.search(text)]


def build_report(path: Path, today: date, skip_calendar: bool = False) -> FreshnessReport:
    text = path.read_text(encoding="utf-8").strip()
    refreshed_at = last_refresh_date(path)
    age_days = (today - refreshed_at).days
    
    warnings = warning_labels(text)
    
    is_sitting_confirmed = None
    if not skip_calendar and SITTING_CLAIM_PATTERN.search(text):
        sitting_days = fetch_sitting_days(today.year)
        # If today is near the end of the year, we might need next year too, 
        # but for staleness 3 days is usually fine.
        sitting_warning = check_sitting_claim(text, today, sitting_days)
        if sitting_warning:
            warnings.append(sitting_warning)
            is_sitting_confirmed = False
        elif sitting_days:
            is_sitting_confirmed = True

    return FreshnessReport(
        path=path,
        text=text,
        last_refreshed_at=refreshed_at,
        age_days=age_days,
        warnings=warnings,
        is_sitting_confirmed=is_sitting_confirmed,
    )


def _linear_team_id(api_key: str) -> str:
    """Resolve the EPAC team ID from Linear."""
    query = """
    query TeamByKey($key: String!) {
      teams(filter: { key: { eq: $key } }) {
        nodes { id name }
      }
    }
    """
    body = json.dumps({"query": query, "variables": {"key": LINEAR_EPAC_TEAM_KEY}}).encode()
    req = Request(
        LINEAR_GRAPHQL_URL,
        data=body,
        headers={"Authorization": api_key, "Content-Type": "application/json"},
    )
    with urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
    nodes = data.get("data", {}).get("teams", {}).get("nodes", [])
    if not nodes:
        raise ValueError(f"No Linear team found with key '{LINEAR_EPAC_TEAM_KEY}'")
    return nodes[0]["id"]


def create_linear_issue(report: FreshnessReport, api_key: str) -> str:
    """Create a Linear ASO refresh task. Returns the new issue URL."""
    team_id = _linear_team_id(api_key)
    age_note = f"{report.age_days} days since last App Store Connect submission"
    warn_note = (
        f"\n\nAdditional copy warnings: {', '.join(report.warnings)}"
        if report.warnings
        else ""
    )
    description = (
        f"The en-CA promotional text is stale ({age_note}).\n\n"
        f"Current text:\n> {report.text}\n\n"
        f"Review the promotional text and submit a fresh version to App Store Connect. "
        f"Update `{report.path.parent}/{report.path.stem}_refreshed_at.txt` with today's date "
        f"after submitting.{warn_note}\n\n"
        f"Ref: `scripts/marketing/check_promotional_text_staleness.py`"
    )
    mutation = """
    mutation CreateIssue($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { id url }
      }
    }
    """
    variables = {
        "input": {
            "teamId": team_id,
            "title": f"ASO: Refresh en-CA promotional text ({report.age_days}d stale)",
            "description": description,
            "labelIds": [],
        }
    }
    body = json.dumps({"query": mutation, "variables": variables}).encode()
    req = Request(
        LINEAR_GRAPHQL_URL,
        data=body,
        headers={"Authorization": api_key, "Content-Type": "application/json"},
    )
    with urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
    issue_create = data.get("data", {}).get("issueCreate", {})
    if not issue_create.get("success"):
        raise RuntimeError(f"Linear issueCreate failed: {data}")
    return issue_create["issue"]["url"]


def render_text(report: FreshnessReport) -> str:
    status = "REFRESH REQUIRED" if report.is_stale else "fresh"
    if report.is_sitting_confirmed is False:
        status = "STALE (SITTING CLAIM FAILED)"

    lines = [
        f"Promotional text file: {report.path}",
        f"Last App Store Connect submission: {report.last_refreshed_at.isoformat()} ({report.age_days} days ago)",
        f"Freshness status: {status}",
    ]
    if report.is_sitting_confirmed is True:
        lines.insert(2, "Sitting status: Confirmed via House of Commons calendar")

    if report.warnings:
        lines.append("Stale-copy risks: " + ", ".join(report.warnings))
    lines.append(f"Current text: {report.text}")
    if report.is_stale:
        lines.append(
            "Next action: run with --create-linear-issue to file a Linear ASO refresh task, "
            "or manually open one before closing the monthly cycle."
        )
    return "\n".join(lines)


def render_json(report: FreshnessReport) -> str:
    payload = {
        "path": str(report.path),
        "text": report.text,
        "last_refreshed_at": report.last_refreshed_at.isoformat(),
        "age_days": report.age_days,
        "warnings": report.warnings,
        "is_stale": report.is_stale,
        "is_sitting_confirmed": report.is_sitting_confirmed,
    }
    return json.dumps(payload, indent=2)


def main() -> int:
    args = parse_args()
    try:
        report = build_report(args.path, args.today, skip_calendar=args.skip_calendar_check)
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(render_json(report) if args.format == "json" else render_text(report))

    if args.create_linear_issue and report.is_stale:
        api_key = os.environ.get("LINEAR_API_KEY", "")
        if not api_key:
            print(
                "error: LINEAR_API_KEY env var is required for --create-linear-issue",
                file=sys.stderr,
            )
            return 1
        try:
            url = create_linear_issue(report, api_key)
            print(f"Linear issue created: {url}")
        except (URLError, RuntimeError, ValueError) as exc:
            print(f"error: failed to create Linear issue: {exc}", file=sys.stderr)
            return 1

    if args.fail_on_stale and report.is_stale:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
