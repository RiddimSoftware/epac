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
    parser.add_argument("--summary-markdown", type=Path)
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
    rows: list[tuple[str, str, str, float | None, float, str, int, str]] = []

    for expected_test in manifest["tests"]:
        for expected_metric in expected_test["metrics"]:
            budget_path = args.manifest.parent / expected_metric["budget"]
            budget = float(budget_path.read_text(encoding="utf-8").strip())
            test = find_test(tests, expected_test["test_identifier"])
            if test is None:
                failures.append(f"missing test metrics for {expected_test['test_identifier']}")
                rows.append((
                    expected_test["test_identifier"],
                    expected_metric["key"],
                    "missing test",
                    None,
                    budget,
                    "",
                    0,
                    "missing",
                ))
                continue

            available_metrics = [
                metric
                for run in test.get("testRuns", [])
                for metric in run.get("metrics", [])
            ]
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
                rows.append((
                    expected_test["test_identifier"],
                    expected_metric["key"],
                    "missing",
                    None,
                    budget,
                    "",
                    0,
                    "missing",
                ))
                continue

            for metric in matches_with_measurements:
                average = mean(float(value) for value in metric["measurements"])
                unit = metric.get("unitOfMeasurement", "")
                sample_count = len(metric["measurements"])
                status = "passed" if average <= budget else "failed"
                rows.append((
                    expected_test["test_identifier"],
                    expected_metric["key"],
                    metric_label(metric),
                    average,
                    budget,
                    unit,
                    sample_count,
                    status,
                ))
                if average > budget:
                    failures.append(
                        f"{expected_test['test_identifier']} {metric_label(metric)} "
                        f"average {average:.6g} {unit} exceeded budget {budget:.6g}"
                    )

    print("In-process performance metrics")
    print("| Test | Expected metric | Reported metric | Average | Budget | Unit | Samples | Status |")
    print("| --- | --- | --- | ---: | ---: | --- | ---: | --- |")
    for test_id, key, label, average, budget, unit, sample_count, status in rows:
        print(
            f"| {test_id} | {key} | {label} | {format_value(average)} | "
            f"{budget:.6g} | {unit} | {sample_count} | {status} |"
        )

    if args.summary_markdown is not None:
        write_summary(args.summary_markdown, rows)

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


def write_summary(
    path: Path,
    rows: list[tuple[str, str, str, float | None, float, str, int, str]],
) -> None:
    lines = ["### In-process performance metrics", ""]
    lines.extend(markdown_table(rows))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def markdown_table(
    rows: list[tuple[str, str, str, float | None, float, str, int, str]],
) -> list[str]:
    if not rows:
        return ["No in-process performance metrics were reported."]

    lines = [
        "| Test | Metric | Reported metric | Budget | Measured average | Unit | Samples | Status |",
        "| --- | --- | --- | ---: | ---: | --- | ---: | --- |",
    ]
    for test_id, key, label, average, budget, unit, sample_count, status in rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    markdown_escape(test_id),
                    markdown_escape(key),
                    markdown_escape(label),
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
