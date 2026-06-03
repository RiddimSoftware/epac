#!/usr/bin/env python3
"""Verify signpost duration metrics are present and within simulator budgets."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from statistics import mean
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-markdown", type=Path)
    parser.add_argument("paths", type=Path, nargs="+")
    return parser.parse_args()


def load_metrics(result_bundle: Path) -> list[dict[str, Any]]:
    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "metrics",
        "--path",
        str(result_bundle),
        "--compact",
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    data = json.loads(completed.stdout)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("tests", "testResults", "metrics"):
            value = data.get(key)
            if isinstance(value, list):
                return value
    raise ValueError("xcresulttool metrics output did not contain a test list")


def matching_test(tests: list[dict[str, Any]], test_method: str) -> dict[str, Any] | None:
    for test in tests:
        identifier = str(test.get("testIdentifier", ""))
        identifier_url = str(test.get("testIdentifierURL", ""))
        if test_method in identifier or test_method in identifier_url:
            return test
    return None


def duration_measurements(test: dict[str, Any], signpost_name: str) -> list[float]:
    values: list[float] = []
    for run in test.get("testRuns", []):
        for metric in run.get("metrics", []):
            if not is_duration_metric(metric, signpost_name):
                continue
            unit = str(metric.get("unitOfMeasurement", "")).lower()
            for measurement in metric.get("measurements", []):
                values.append(to_seconds(float(measurement), unit))
    return values


def is_duration_metric(metric: dict[str, Any], signpost_name: str) -> bool:
    display_name = str(metric.get("displayName", "")).lower()
    unit = str(metric.get("unitOfMeasurement", "")).lower()
    has_duration_unit = unit in {"s", "sec", "secs", "second", "seconds", "ms", "millisecond", "milliseconds"}
    return signpost_name.lower() in display_name and ("duration" in display_name or has_duration_unit)


def to_seconds(value: float, unit: str) -> float:
    if unit in {"ms", "millisecond", "milliseconds"}:
        return value / 1000.0
    return value


def main() -> int:
    args = parse_args()
    if len(args.paths) < 2:
        raise ValueError("provide one or more result bundles followed by the budget file")

    result_bundles = args.paths[:-1]
    budget_file = args.paths[-1]
    budgets = json.loads(budget_file.read_text(encoding="utf-8"))
    expected_metrics = budgets["metrics"]
    tests: list[dict[str, Any]] = []
    for result_bundle in result_bundles:
        tests.extend(load_metrics(result_bundle))

    failures: list[str] = []
    summaries: list[str] = []
    rows: list[tuple[str, str, float | None, float, str, int, str]] = []
    for expected in expected_metrics:
        max_seconds = float(expected["max_seconds"])
        test = matching_test(tests, expected["test_method"])
        if test is None:
            failures.append(f"{expected['name']}: missing test method {expected['test_method']}")
            rows.append((
                expected["name"],
                expected["test_method"],
                None,
                max_seconds,
                "s",
                0,
                "missing",
            ))
            continue

        measurements = duration_measurements(test, expected["name"])
        if not measurements:
            failures.append(f"{expected['name']}: missing duration measurements")
            rows.append((
                expected["name"],
                expected["test_method"],
                None,
                max_seconds,
                "s",
                0,
                "missing",
            ))
            continue

        average = mean(measurements)
        status = "passed" if average <= max_seconds else "failed"
        rows.append((
            expected["name"],
            expected["test_method"],
            average,
            max_seconds,
            "s",
            len(measurements),
            status,
        ))
        summaries.append(f"{expected['name']}: average={average:.3f}s budget={max_seconds:.3f}s samples={len(measurements)}")
        if average > max_seconds:
            failures.append(f"{expected['name']}: average {average:.3f}s exceeded budget {max_seconds:.3f}s")

    print("\n".join(summaries))
    if args.summary_markdown is not None:
        write_summary(args.summary_markdown, rows)
    if failures:
        print("\nSignpost performance guard failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    return 0


def write_summary(
    path: Path,
    rows: list[tuple[str, str, float | None, float, str, int, str]],
) -> None:
    lines = ["### Signpost performance metrics", ""]
    lines.extend(markdown_table(rows))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def markdown_table(
    rows: list[tuple[str, str, float | None, float, str, int, str]],
) -> list[str]:
    if not rows:
        return ["No signpost performance metrics were reported."]

    lines = [
        "| Metric | Test | Budget | Measured average | Unit | Samples | Status |",
        "| --- | --- | ---: | ---: | --- | ---: | --- |",
    ]
    for name, test_method, average, budget, unit, sample_count, status in rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    markdown_escape(name),
                    markdown_escape(test_method),
                    f"{budget:.6g}",
                    format_value(average),
                    markdown_escape(unit),
                    str(sample_count),
                    status,
                ]
            )
            + " |"
        )
    return lines


def format_value(value: float | None) -> str:
    if value is None:
        return "missing"
    return f"{value:.6g}"


def markdown_escape(value: str) -> str:
    return value.replace("|", "\\|")


if __name__ == "__main__":
    raise SystemExit(main())
