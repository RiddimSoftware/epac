#!/usr/bin/env python3
"""Summarize iOS xccov JSON and enforce module coverage thresholds."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import sys


MODULE_THRESHOLDS = {
    "ViewModels": 60.0,
    "Services": 50.0,
    "Models": 40.0,
    "Views": 0.0,
}


@dataclass
class Coverage:
    covered: int = 0
    executable: int = 0

    @property
    def percent(self) -> float:
        if self.executable == 0:
            return 100.0
        return round((self.covered / self.executable) * 100, 2)

    def add(self, covered: int, executable: int) -> None:
        self.covered += covered
        self.executable += executable


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize iOS xccov JSON")
    parser.add_argument("--coverage-json", required=True, type=Path)
    parser.add_argument("--base-coverage-json", type=Path)
    parser.add_argument("--changed-files", type=Path)
    parser.add_argument("--summary-md", required=True, type=Path)
    parser.add_argument("--comment-md", required=True, type=Path)
    parser.add_argument("--json-output", required=True, type=Path)
    args = parser.parse_args()

    current = summarize(load_json(args.coverage_json))
    baseline = summarize(load_json(args.base_coverage_json)) if args.base_coverage_json else {}
    changed_modules = modules_from_changed_files(args.changed_files) if args.changed_files else set()
    failures = threshold_failures(current, changed_modules)

    args.summary_md.write_text(render_summary(current, baseline, changed_modules, failures), encoding="utf-8")
    args.comment_md.write_text(render_comment(current, baseline, changed_modules, failures), encoding="utf-8")
    args.json_output.write_text(
        json.dumps(
            {
                "modules": {
                    module: {
                        "covered_lines": coverage.covered,
                        "executable_lines": coverage.executable,
                        "line_coverage": coverage.percent,
                    }
                    for module, coverage in sorted(current.items())
                },
                "changed_modules": sorted(changed_modules),
                "failures": failures,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    if failures:
        for failure in failures:
            print(f"::error::{failure}")
        return 1
    return 0


def load_json(path: Path | None) -> dict:
    if path is None or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def summarize(report: dict) -> dict[str, Coverage]:
    modules: dict[str, Coverage] = {module: Coverage() for module in [*MODULE_THRESHOLDS, "Other"]}
    for target in report.get("targets", []):
        for file_report in target.get("files", []):
            path = file_report.get("path", "")
            if "/ios/epac/" not in path or not path.endswith(".swift"):
                continue
            module = classify(path)
            modules.setdefault(module, Coverage()).add(
                int(file_report.get("coveredLines", 0)),
                int(file_report.get("executableLines", 0)),
            )
    return {module: coverage for module, coverage in modules.items() if coverage.executable > 0}


def modules_from_changed_files(path: Path) -> set[str]:
    if not path.exists():
        return set()
    modules: set[str] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        changed_path = raw_line.strip()
        if changed_path.startswith("ios/epac/") and changed_path.endswith(".swift"):
            modules.add(classify(changed_path))
    return modules


def classify(path: str) -> str:
    if path.endswith("ViewModel.swift") or "/ViewModels/" in path:
        return "ViewModels"
    if "/Util/" in path and (path.endswith("Service.swift") or path.endswith("Manager.swift")):
        return "Services"
    if "/Model/" in path:
        return "Models"
    if "/Views/" in path:
        return "Views"
    return "Other"


def threshold_failures(current: dict[str, Coverage], changed_modules: set[str]) -> list[str]:
    failures: list[str] = []
    for module, threshold in MODULE_THRESHOLDS.items():
        if module not in changed_modules or threshold <= 0:
            continue
        percent = current.get(module, Coverage()).percent
        if percent < threshold:
            failures.append(f"{module} coverage is {percent:.2f}%, below the {threshold:.0f}% threshold")
    return failures


def render_summary(
    current: dict[str, Coverage],
    baseline: dict[str, Coverage],
    changed_modules: set[str],
    failures: list[str],
) -> str:
    lines = [
        "## iOS Code Coverage",
        "",
        "| Module | Coverage | Delta | Threshold | Changed in PR |",
        "| --- | ---: | ---: | ---: | --- |",
    ]
    for module in sorted(current):
        coverage = current[module]
        threshold = MODULE_THRESHOLDS.get(module, 0.0)
        delta = delta_label(coverage, baseline.get(module))
        changed = "yes" if module in changed_modules else "no"
        lines.append(f"| {module} | {coverage.percent:.2f}% | {delta} | {threshold:.0f}% | {changed} |")

    if failures:
        lines.extend(["", "### Failures", ""])
        lines.extend(f"- {failure}" for failure in failures)
    else:
        lines.extend(["", "No changed module is below its configured coverage threshold."])
    return "\n".join(lines) + "\n"


def render_comment(
    current: dict[str, Coverage],
    baseline: dict[str, Coverage],
    changed_modules: set[str],
    failures: list[str],
) -> str:
    if not changed_modules:
        return "Coverage changed: no app Swift modules changed in this PR.\n"

    parts = []
    for module in sorted(changed_modules):
        coverage = current.get(module, Coverage())
        base = baseline.get(module)
        if base is None:
            parts.append(f"{module} {coverage.percent:.2f}% (baseline unavailable)")
        else:
            delta = coverage.percent - base.percent
            parts.append(f"{module} {base.percent:.2f}% -> {coverage.percent:.2f}% ({delta:+.2f}%)")
    body = "Coverage changed: " + "; ".join(parts) + ".\n"
    if failures:
        body += "\nThreshold failures:\n" + "\n".join(f"- {failure}" for failure in failures) + "\n"
    return body


def delta_label(current: Coverage, baseline: Coverage | None) -> str:
    if baseline is None:
        return "n/a"
    delta = current.percent - baseline.percent
    return f"{delta:+.2f}%"


if __name__ == "__main__":
    raise SystemExit(main())
