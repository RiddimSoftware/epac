#!/usr/bin/env python3
"""Validate in-process XCTest metrics against committed simulator budgets."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from statistics import mean


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    metrics_json = subprocess.check_output(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "metrics",
            "--path",
            str(args.xcresult),
            "--compact",
        ],
        text=True,
    )
    tests = collect_tests(json.loads(metrics_json))
    failures: list[str] = []
    rows: list[tuple[str, str, str, float, float, str]] = []

    for expected_test in manifest["tests"]:
        test = find_test(tests, expected_test["test_identifier"])
        if test is None:
            failures.append(f"missing test metrics for {expected_test['test_identifier']}")
            continue

        available_metrics = [
            metric
            for run in test.get("testRuns", [])
            for metric in run.get("metrics", [])
        ]
        for expected_metric in expected_test["metrics"]:
            matches = matching_metrics(available_metrics, expected_metric["match"])
            matches_with_measurements = [
                metric for metric in matches if metric.get("measurements")
            ]
            if not matches_with_measurements:
                available_names = ", ".join(
                    sorted({
                        metric_label(metric)
                        for metric in available_metrics
                    })
                )
                failures.append(
                    "missing non-empty metric "
                    f"{expected_metric['key']} for {expected_test['test_identifier']} "
                    f"(available: {available_names or 'none'})"
                )
                continue

            budget_path = args.manifest.parent / expected_metric["budget"]
            budget = float(budget_path.read_text(encoding="utf-8").strip())
            for metric in matches_with_measurements:
                average = mean(float(value) for value in metric["measurements"])
                unit = metric.get("unitOfMeasurement", "")
                rows.append((
                    expected_test["test_identifier"],
                    expected_metric["key"],
                    metric_label(metric),
                    average,
                    budget,
                    unit,
                ))
                if average > budget:
                    failures.append(
                        f"{expected_test['test_identifier']} {metric_label(metric)} "
                        f"average {average:.6g} {unit} exceeded budget {budget:.6g}"
                    )

    print("In-process performance metrics")
    print("| Test | Expected metric | Reported metric | Average | Budget | Unit |")
    print("| --- | --- | --- | ---: | ---: | --- |")
    for test_id, key, label, average, budget, unit in rows:
        print(f"| {test_id} | {key} | {label} | {average:.6g} | {budget:.6g} | {unit} |")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    return 0


def collect_tests(value: object) -> list[dict]:
    tests: list[dict] = []
    if isinstance(value, dict):
        if "testIdentifier" in value and "testRuns" in value:
            tests.append(value)
        for child in value.values():
            tests.extend(collect_tests(child))
    elif isinstance(value, list):
        for child in value:
            tests.extend(collect_tests(child))
    return tests


def find_test(tests: list[dict], expected_identifier: str) -> dict | None:
    for test in tests:
        candidates = [
            str(test.get("testIdentifier", "")),
            str(test.get("testIdentifierURL", "")),
        ]
        if any(expected_identifier in candidate for candidate in candidates):
            return test
    return None


def matching_metrics(metrics: list[dict], matchers: list[str]) -> list[dict]:
    normalized_matchers = [normalize(matcher) for matcher in matchers]
    return [
        metric
        for metric in metrics
        if any(matcher in normalize(metric_label(metric)) for matcher in normalized_matchers)
    ]


def metric_label(metric: dict) -> str:
    parts = [
        str(metric.get("displayName", "")),
        str(metric.get("identifier", "")),
    ]
    return " ".join(part for part in parts if part).strip()


def normalize(value: str) -> str:
    return value.lower().replace("_", " ").replace("-", " ")


if __name__ == "__main__":
    raise SystemExit(main())
