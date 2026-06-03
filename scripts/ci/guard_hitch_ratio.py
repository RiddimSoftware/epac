#!/usr/bin/env python3
"""Fail if device performance output lacks a non-empty hitch-ratio measurement."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--budget", required=True, type=Path)
    return parser.parse_args()


def hitch_ratio_measurements(log_text: str) -> list[float]:
    measurements: list[float] = []
    for line in log_text.splitlines():
        lowered = line.lower()
        if "hitch" not in lowered or "ratio" not in lowered:
            continue
        patterns = [
            r"average[=:]\s*(\d+(?:\.\d+)?)",
            r"measured\s*\(\s*(\d+(?:\.\d+)?)\s*ms/s\b",
            r"(\d+(?:\.\d+)?)\s*ms/s\b",
        ]
        for pattern in patterns:
            if match := re.search(pattern, line, flags=re.IGNORECASE):
                measurements.append(float(match.group(1)))
                break
    return measurements


def main() -> int:
    args = parse_args()
    budget = float(args.budget.read_text(encoding="utf-8").strip())
    measurements = hitch_ratio_measurements(args.log.read_text(encoding="utf-8", errors="replace"))

    if not measurements:
        print("Missing non-empty hitch-ratio measurement in device performance output.", file=sys.stderr)
        return 1

    worst = max(measurements)
    if worst >= budget:
        print(f"Hitch-ratio budget exceeded: {worst:g} ms/s >= {budget:g} ms/s", file=sys.stderr)
        return 1

    print(f"Hitch-ratio guard passed: worst {worst:g} ms/s < {budget:g} ms/s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
