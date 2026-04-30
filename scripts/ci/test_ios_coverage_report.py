#!/usr/bin/env python3
"""Unit tests for the iOS coverage summary helper."""

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))

import ios_coverage_report


def report_with_files(files: list[dict]) -> dict:
    return {"targets": [{"name": "epac.app", "files": files}]}


def swift_file(path: str, covered: int, executable: int) -> dict:
    return {
        "path": path,
        "coveredLines": covered,
        "executableLines": executable,
    }


class CoverageReportTests(unittest.TestCase):
    def test_summarize_groups_ios_app_files_by_module(self) -> None:
        report = report_with_files(
            [
                swift_file("/tmp/build/ios/epac/ViewModels/HomeViewModel.swift", 6, 10),
                swift_file("/tmp/build/ios/epac/Util/NetworkService.swift", 5, 10),
                swift_file("/tmp/build/ios/epac/Util/CacheManager.swift", 4, 10),
                swift_file("/tmp/build/ios/epac/Model/Bill.swift", 3, 10),
                swift_file("/tmp/build/ios/epac/Views/HomeView.swift", 2, 10),
                swift_file("/tmp/build/ios/epac/AppDelegate.swift", 1, 10),
                swift_file("/tmp/build/ios/epacTests/HomeViewModelTests.swift", 10, 10),
            ]
        )

        summary = ios_coverage_report.summarize(report)

        self.assertEqual(summary["ViewModels"].percent, 60.0)
        self.assertEqual(summary["Services"].percent, 45.0)
        self.assertEqual(summary["Models"].percent, 30.0)
        self.assertEqual(summary["Views"].percent, 20.0)
        self.assertEqual(summary["Other"].percent, 10.0)

    def test_changed_files_only_include_app_swift_modules(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "changed-files.txt"
            changed.write_text(
                "\n".join(
                    [
                        "ios/epac/ViewModels/HomeViewModel.swift",
                        "ios/epac/Util/NetworkService.swift",
                        "ios/epacTests/HomeViewModelTests.swift",
                        "docs/readme.md",
                    ]
                ),
                encoding="utf-8",
            )

            modules = ios_coverage_report.modules_from_changed_files(changed)

        self.assertEqual(modules, {"ViewModels", "Services"})

    def test_thresholds_are_enforced_only_for_changed_modules(self) -> None:
        current = {
            "ViewModels": ios_coverage_report.Coverage(covered=59, executable=100),
            "Services": ios_coverage_report.Coverage(covered=49, executable=100),
            "Models": ios_coverage_report.Coverage(covered=39, executable=100),
        }

        failures = ios_coverage_report.threshold_failures(current, {"ViewModels", "Models"})

        self.assertEqual(
            failures,
            [
                "ViewModels coverage is 59.00%, below the 60% threshold",
                "Models coverage is 39.00%, below the 40% threshold",
            ],
        )

    def test_render_comment_reports_baseline_delta_and_failures(self) -> None:
        current = {"ViewModels": ios_coverage_report.Coverage(covered=59, executable=100)}
        baseline = {"ViewModels": ios_coverage_report.Coverage(covered=62, executable=100)}
        failures = ["ViewModels coverage is 59.00%, below the 60% threshold"]

        comment = ios_coverage_report.render_comment(current, baseline, {"ViewModels"}, failures)

        self.assertIn("ViewModels 62.00% -> 59.00% (-3.00%)", comment)
        self.assertIn("Threshold failures:", comment)


if __name__ == "__main__":
    unittest.main()
