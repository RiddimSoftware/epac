#!/usr/bin/env python3
"""Verify launch + memory perf measurements are present and within sim budgets.

Reads an xcresult bundle produced by `make perf-sim` and asserts that the
`LaunchPerfTests/testLaunchAndMemoryBaseline` test produced both:

* an `XCTApplicationLaunchMetric` duration (seconds), and
* an `XCTMemoryMetric` peak physical value (kilobytes),

then compares each average against its simulator budget file.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from statistics import mean
from typing import Any, Callable


TEST_METHOD = "testLaunchAndMemoryBaseline"

SECONDS_UNITS = {"s", "sec", "secs", "second", "seconds"}
MILLISECONDS_UNITS = {"ms", "millisecond", "milliseconds"}
KILOBYTE_UNITS = {"kb", "kilobyte", "kilobytes"}
MEGABYTE_UNITS = {"mb", "megabyte", "megabytes"}
BYTE_UNITS = {"b", "byte", "bytes"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument(
        "launch_budget_file",
        type=Path,
        help="Path to launch-time-seconds.sim.txt (single float, seconds).",
    )
    parser.add_argument(
        "memory_budget_file",
        type=Path,
        help="Path to memory-physical-kb.sim.txt (single number, kilobytes).",
    )
    return parser.parse_args()


def load_tests(result_bundle: Path) -> list[dict[str, Any]]:
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


def collect_measurements(
    test: dict[str, Any],
    select: Callable[[str, str], float | None],
) -> list[float]:
    """For each metric on the test, call `select(display_name, unit)`; if it
    returns a scale factor (or 1.0) the metric's raw measurements are scaled
    and collected. Returning None skips the metric."""
    values: list[float] = []
    for run in test.get("testRuns", []):
        for metric in run.get("metrics", []):
            display_name = str(metric.get("displayName", "")).lower()
            unit = str(metric.get("unitOfMeasurement", "")).lower()
            scale = select(display_name, unit)
            if scale is None:
                continue
            for raw in metric.get("measurements", []):
                values.append(float(raw) * scale)
    return values


def select_launch_seconds(display_name: str, unit: str) -> float | None:
    if "memory" in display_name:
        return None
    if unit in SECONDS_UNITS:
        return 1.0
    if unit in MILLISECONDS_UNITS:
        return 1.0 / 1000.0
    return None


def select_memory_peak_kilobytes(display_name: str, unit: str) -> float | None:
    if "memory" not in display_name or "peak" not in display_name:
        return None
    if unit in KILOBYTE_UNITS:
        return 1.0
    if unit in MEGABYTE_UNITS:
        return 1000.0
    if unit in BYTE_UNITS:
        return 1.0 / 1000.0
    return None


def main() -> int:
    args = parse_args()
    launch_budget = float(args.launch_budget_file.read_text(encoding="utf-8").strip())
    memory_budget = float(args.memory_budget_file.read_text(encoding="utf-8").strip())

    tests = load_tests(args.result_bundle)
    test = matching_test(tests, TEST_METHOD)
    if test is None:
        print(
            f"Launch performance guard failed: missing test method {TEST_METHOD}",
            file=sys.stderr,
        )
        return 1

    launch_seconds = collect_measurements(test, select_launch_seconds)
    memory_kb = collect_measurements(test, select_memory_peak_kilobytes)

    failures: list[str] = []
    summaries: list[str] = []

    if not launch_seconds:
        failures.append("XCTApplicationLaunchMetric: no duration measurements found")
    else:
        avg = mean(launch_seconds)
        summaries.append(
            f"launch.duration: average={avg:.3f}s budget={launch_budget:.3f}s samples={len(launch_seconds)}"
        )
        if avg > launch_budget:
            failures.append(
                f"launch.duration: average {avg:.3f}s exceeded budget {launch_budget:.3f}s"
            )

    if not memory_kb:
        failures.append("XCTMemoryMetric: no memory measurements found")
    else:
        avg = mean(memory_kb)
        summaries.append(
            f"app.memory-peak-physical: average={avg:.0f}kB budget={memory_budget:.0f}kB samples={len(memory_kb)}"
        )
        if avg > memory_budget:
            failures.append(
                f"app.memory-peak-physical: average {avg:.0f}kB exceeded budget {memory_budget:.0f}kB"
            )

    if summaries:
        print("\n".join(summaries))
    if failures:
        print("\nLaunch performance guard failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
