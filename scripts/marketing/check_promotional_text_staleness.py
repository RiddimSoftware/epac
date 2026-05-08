#!/usr/bin/env python3
"""Check whether the en-CA promotional text needs a monthly refresh."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date
import json
from pathlib import Path
import re
import subprocess
import sys

DEFAULT_PROMOTIONAL_TEXT_PATH = Path("ios/fastlane/metadata/en-CA/promotional_text.txt")
MAX_AGE_DAYS = 30
STALE_PATTERNS = {
    "hard-coded Parliament number": re.compile(r"\b\d{1,2}(?:st|nd|rd|th) Parliament\b", re.IGNORECASE),
    "uses 'free'": re.compile(r"\bfree\b", re.IGNORECASE),
}


@dataclass(frozen=True)
class FreshnessReport:
    path: Path
    text: str
    last_refreshed_at: date
    age_days: int
    warnings: list[str]

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
    return parser.parse_args()


def last_refresh_date(path: Path) -> date:
    result = subprocess.run(
        ["git", "log", "-1", "--format=%cs", "--", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    refresh_date = result.stdout.strip()
    if not refresh_date:
        raise ValueError(f"no git history found for {path}")
    return date.fromisoformat(refresh_date)


def warning_labels(text: str) -> list[str]:
    return [label for label, pattern in STALE_PATTERNS.items() if pattern.search(text)]


def build_report(path: Path, today: date) -> FreshnessReport:
    text = path.read_text(encoding="utf-8").strip()
    refreshed_at = last_refresh_date(path)
    age_days = (today - refreshed_at).days
    return FreshnessReport(
        path=path,
        text=text,
        last_refreshed_at=refreshed_at,
        age_days=age_days,
        warnings=warning_labels(text),
    )


def render_text(report: FreshnessReport) -> str:
    lines = [
        f"Promotional text file: {report.path}",
        f"Promotional text last refreshed: {report.last_refreshed_at.isoformat()} ({report.age_days} days ago)",
        f"Freshness status: {'REFRESH REQUIRED' if report.is_stale else 'fresh'}",
    ]
    if report.warnings:
        lines.append("Stale-copy risks: " + ", ".join(report.warnings))
    lines.extend(
        [
            f"Current text: {report.text}",
            "Next action: open a Linear ASO refresh task if the text is older than 30 days or contains stale factual wording.",
        ]
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
        "next_action": "open a Linear ASO refresh task if the text is older than 30 days or contains stale factual wording",
    }
    return json.dumps(payload, indent=2)


def main() -> int:
    args = parse_args()
    try:
        report = build_report(args.path, args.today)
    except (FileNotFoundError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(render_json(report) if args.format == "json" else render_text(report))
    if args.fail_on_stale and report.is_stale:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
