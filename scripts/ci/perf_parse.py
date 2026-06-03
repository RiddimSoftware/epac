#!/usr/bin/env python3
"""Report XCTest performance metrics and fail when expected metrics are absent."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Any, Callable


SECONDS_UNITS = {"s", "sec", "secs", "second", "seconds"}
MILLISECONDS_UNITS = {"ms", "millisecond", "milliseconds"}
KILOBYTE_UNITS = {"kb", "kilobyte", "kilobytes"}
MEGABYTE_UNITS = {"mb", "megabyte", "megabytes"}
BYTE_UNITS = {"b", "byte", "bytes"}
LAUNCH_BASELINE_TEST = "testLaunchAndMemoryBaseline"


@dataclass(frozen=True)
class MetricReport:
    test_name: str
    metric_name: str
    average: float | None
    unit: str
    sample_count: int
    present: bool


@dataclass(frozen=True)
class MetricDefinition:
    name: str
    test_method: str | None
    selector: Callable[[str, str], bool]
    converter: Callable[[float, str], float]
    unit: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument(
        "--budget-dir",
        type=Path,
        help="Directory containing <metric>.<platform>.txt budget files to use as expected metrics.",
    )
    parser.add_argument(
        "--platform",
        choices=("sim", "device"),
        default="sim",
        help="Budget filename platform suffix to read when --budget-dir is provided.",
    )
    parser.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="METRIC",
        help="Expected metric name. Can be supplied more than once.",
    )
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
    return parse_metrics_json(completed.stdout)


def parse_metrics_json(raw_json: str) -> list[dict[str, Any]]:
    data = json.loads(raw_json)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("tests", "testResults", "metrics"):
            value = data.get(key)
            if isinstance(value, list):
                return value
    raise ValueError("xcresulttool metrics output did not contain a test list")


def expected_metrics_from_budget_dir(budget_dir: Path, platform: str) -> list[str]:
    suffix = f".{platform}.txt"
    if not budget_dir.exists():
        return []
    return sorted(
        path.name.removesuffix(suffix)
        for path in budget_dir.glob(f"*{suffix}")
        if path.is_file()
    )


def known_metric_definitions() -> dict[str, MetricDefinition]:
    return {
        "launch-time-seconds": MetricDefinition(
            name="launch-time-seconds",
            test_method=LAUNCH_BASELINE_TEST,
            selector=is_launch_duration_metric,
            converter=to_seconds,
            unit="s",
        ),
        "memory-physical-kb": MetricDefinition(
            name="memory-physical-kb",
            test_method=LAUNCH_BASELINE_TEST,
            selector=is_memory_physical_metric,
            converter=to_kilobytes,
            unit="kB",
        ),
    }


def collect_reports(
    tests: list[dict[str, Any]],
    expected_metric_names: list[str],
) -> list[MetricReport]:
    definitions = known_metric_definitions()
    if expected_metric_names:
        return [
            collect_expected_metric(tests, definitions.get(metric_name) or generic_definition(metric_name))
            for metric_name in expected_metric_names
        ]

    reports: list[MetricReport] = []
    for test in tests:
        test_name = display_test_name(test)
        for run in test.get("testRuns", []):
            for metric in run.get("metrics", []):
                values = [float(value) for value in metric.get("measurements", [])]
                metric_name = slugify(str(metric.get("displayName", "")))
                unit = str(metric.get("unitOfMeasurement", ""))
                reports.append(
                    MetricReport(
                        test_name=test_name,
                        metric_name=metric_name,
                        average=mean(values) if values else None,
                        unit=unit,
                        sample_count=len(values),
                        present=bool(values),
                    )
                )
    return reports


def collect_expected_metric(
    tests: list[dict[str, Any]],
    definition: MetricDefinition,
) -> MetricReport:
    candidate_tests = tests
    if definition.test_method is not None:
        candidate_tests = [
            test for test in tests if definition.test_method in test_identifier(test)
        ]

    for test in candidate_tests:
        values: list[float] = []
        for run in test.get("testRuns", []):
            for metric in run.get("metrics", []):
                display_name = str(metric.get("displayName", ""))
                unit = str(metric.get("unitOfMeasurement", ""))
                if not definition.selector(display_name.lower(), unit.lower()):
                    continue
                values.extend(
                    definition.converter(float(measurement), unit.lower())
                    for measurement in metric.get("measurements", [])
                )
        if values:
            return MetricReport(
                test_name=display_test_name(test),
                metric_name=definition.name,
                average=mean(values),
                unit=definition.unit,
                sample_count=len(values),
                present=True,
            )

    return MetricReport(
        test_name=definition.test_method or "*",
        metric_name=definition.name,
        average=None,
        unit=definition.unit,
        sample_count=0,
        present=False,
    )


def generic_definition(metric_name: str) -> MetricDefinition:
    return MetricDefinition(
        name=metric_name,
        test_method=None,
        selector=lambda display_name, _unit: slugify(display_name) == metric_name,
        converter=lambda value, _unit: value,
        unit="raw",
    )


def is_launch_duration_metric(display_name: str, unit: str) -> bool:
    return "memory" not in display_name and unit in SECONDS_UNITS | MILLISECONDS_UNITS


def is_memory_physical_metric(display_name: str, unit: str) -> bool:
    return (
        "memory" in display_name
        and "peak" in display_name
        and "physical" in display_name
        and unit in KILOBYTE_UNITS | MEGABYTE_UNITS | BYTE_UNITS
    )


def to_seconds(value: float, unit: str) -> float:
    if unit in MILLISECONDS_UNITS:
        return value / 1000.0
    return value


def to_kilobytes(value: float, unit: str) -> float:
    if unit in MEGABYTE_UNITS:
        return value * 1000.0
    if unit in BYTE_UNITS:
        return value / 1000.0
    return value


def test_identifier(test: dict[str, Any]) -> str:
    identifier = str(test.get("testIdentifier", ""))
    identifier_url = str(test.get("testIdentifierURL", ""))
    return f"{identifier} {identifier_url}"


def display_test_name(test: dict[str, Any]) -> str:
    identifier = str(test.get("testIdentifier", "")) or str(test.get("testIdentifierURL", ""))
    if "/" in identifier:
        return identifier
    match = re.search(r"/([^/]+)/([^/()]+)\(\)", identifier)
    if match:
        return "/".join(match.groups())
    return identifier or "unknown-test"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "unknown-metric"


def format_report(report: MetricReport) -> str:
    average = "missing" if report.average is None else f"{report.average:.6g}"
    return (
        f"test={report.test_name} metric={report.metric_name} "
        f"average={average} unit={report.unit} "
        f"measurement_line_present={str(report.present).lower()} samples={report.sample_count}"
    )


def main() -> int:
    args = parse_args()
    expected_metric_names = list(args.expect)
    if args.budget_dir is not None:
        expected_metric_names.extend(
            expected_metrics_from_budget_dir(args.budget_dir, args.platform)
        )
    expected_metric_names = sorted(set(expected_metric_names))

    reports = collect_reports(load_metrics(args.result_bundle), expected_metric_names)
    for report in reports:
        print(format_report(report))

    missing = [report.metric_name for report in reports if not report.present]
    if missing:
        print(
            f"Performance metric parser failed: missing expected metric(s): {', '.join(missing)}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
