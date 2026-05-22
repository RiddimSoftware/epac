#!/usr/bin/env python3
"""Parse GitHub intake issue markers for Linear field sync."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys


SF_TO_LINEAR_ESTIMATE = {
    1: 1,
    2: 2,
    4: 4,
    8: 8,
    16: 16,
    32: 24,
    64: 40,
}

REQUIRED_MARKERS = ("Estimate", "Mode", "Reporter-Email")
MARKER_RE = re.compile(r"^\s*([A-Za-z][A-Za-z-]*):\s*(.*?)\s*$")


@dataclass(frozen=True)
class IntakeMarkers:
    estimate_sf: int
    estimate_linear: int
    mode: str
    reporter_email: str
    priority: int


@dataclass(frozen=True)
class ParseResult:
    should_sync: bool
    markers: IntakeMarkers | None = None
    error: str = ""


def priority_for_mode(mode: str) -> int:
    """Return Linear priority number. Linear uses 3 for Medium and 4 for Low."""
    return 3 if mode.strip().lower() == "bug" else 4


def _extract_marker_values(body: str) -> dict[str, str]:
    markers: dict[str, str] = {}
    for line in body.splitlines():
        match = MARKER_RE.match(line)
        if match:
            markers[match.group(1).lower()] = match.group(2).strip()
    return markers


def parse_markers(body: str) -> IntakeMarkers:
    values = _extract_marker_values(body)
    missing = [name for name in REQUIRED_MARKERS if not values.get(name.lower())]
    if missing:
        raise ValueError(f"Missing required intake marker(s): {', '.join(missing)}")

    try:
        estimate_sf = int(values["estimate"])
    except ValueError as exc:
        raise ValueError(f"Estimate must be an integer: {values['estimate']}") from exc

    if estimate_sf not in SF_TO_LINEAR_ESTIMATE:
        supported = ", ".join(str(value) for value in SF_TO_LINEAR_ESTIMATE)
        raise ValueError(
            f"Unsupported Estimate: {estimate_sf}. Supported SF estimates: {supported}"
        )

    mode = values["mode"].strip().lower()
    reporter_email = values["reporter-email"].strip()
    return IntakeMarkers(
        estimate_sf=estimate_sf,
        estimate_linear=SF_TO_LINEAR_ESTIMATE[estimate_sf],
        mode=mode,
        reporter_email=reporter_email,
        priority=priority_for_mode(mode),
    )


def parse_body(body: str) -> ParseResult:
    try:
        return ParseResult(should_sync=True, markers=parse_markers(body))
    except ValueError as exc:
        return ParseResult(should_sync=False, error=str(exc))


def _write_github_output(result: ParseResult, output_path: str | None) -> None:
    if not output_path:
        return

    lines = [f"should_sync={'true' if result.should_sync else 'false'}"]
    if result.markers:
        lines.extend(
            [
                f"estimate_sf={result.markers.estimate_sf}",
                f"estimate_linear={result.markers.estimate_linear}",
                f"mode={result.markers.mode}",
                f"reporter_email={result.markers.reporter_email}",
                f"priority={result.markers.priority}",
            ]
        )
    if result.error:
        lines.append(f"error={result.error}")

    with open(output_path, "a", encoding="utf-8") as output:
        output.write("\n".join(lines))
        output.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--body-file", required=True)
    args = parser.parse_args(argv)

    body = Path(args.body_file).read_text(encoding="utf-8")
    result = parse_body(body)
    _write_github_output(result, os.environ.get("GITHUB_OUTPUT"))

    if result.should_sync and result.markers:
        print(
            "Parsed intake markers: "
            f"Estimate {result.markers.estimate_sf} -> {result.markers.estimate_linear}, "
            f"Mode {result.markers.mode}, Priority {result.markers.priority}"
        )
    else:
        print(f"Intake marker sync skipped: {result.error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
