#!/usr/bin/env python3
"""Unit tests for check_promotional_text_staleness.py."""

from __future__ import annotations

from datetime import date
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent / "check_promotional_text_staleness.py"
spec = importlib.util.spec_from_file_location("promotional_text_staleness", SCRIPT)
MODULE = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = MODULE
spec.loader.exec_module(MODULE)


class PromotionalTextStalenessTests(unittest.TestCase):
    def setUp(self) -> None:
        # Default mock to avoid network calls
        self.original_fetch = MODULE.fetch_sitting_days
        MODULE.fetch_sitting_days = lambda year: set()

    def tearDown(self) -> None:
        MODULE.fetch_sitting_days = self.original_fetch

    def test_warning_labels_flags_time_bound_copy_and_free(self) -> None:
        warnings = MODULE.warning_labels(
            "Canada's 45th Parliament is sitting. Official sources. Free."
        )

        self.assertEqual(warnings, ["hard-coded Parliament number", "uses 'free'"])

    def test_build_report_is_stale_when_age_exceeds_30_days(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "promotional_text.txt"
            temp_path.write_text("Parliament is sitting.", encoding="utf-8")
            
            date_path = Path(temp_dir) / "promotional_text_refreshed_at.txt"
            date_path.write_text("2026-04-01", encoding="utf-8")

            report = MODULE.build_report(temp_path, date(2026, 5, 7))

        self.assertEqual(report.age_days, 36)
        self.assertTrue(report.is_stale)
        self.assertEqual(report.warnings, [])

    def test_build_report_is_fresh_with_recent_clean_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "promotional_text.txt"
            temp_path.write_text(
                "Parliament is sitting. Follow every vote — verified from Hansard.",
                encoding="utf-8",
            )
            
            date_path = Path(temp_dir) / "promotional_text_refreshed_at.txt"
            date_path.write_text("2026-05-01", encoding="utf-8")

            report = MODULE.build_report(temp_path, date(2026, 5, 7))

        self.assertEqual(report.age_days, 6)
        self.assertFalse(report.is_stale)
        self.assertEqual(report.warnings, [])

    def test_last_refresh_date_missing_file_raises_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "promotional_text.txt"
            
            with self.assertRaises(FileNotFoundError):
                MODULE.last_refresh_date(temp_path)

    def test_last_refresh_date_invalid_format_raises_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "promotional_text.txt"
            date_path = Path(temp_dir) / "promotional_text_refreshed_at.txt"
            date_path.write_text("invalid-date", encoding="utf-8")
            
            with self.assertRaises(ValueError) as cm:
                MODULE.last_refresh_date(temp_path)
            self.assertIn("must contain a YYYY-MM-DD date", str(cm.exception))

    def test_sitting_claim_validation_flags_stale_sitting_status(self) -> None:
        text = "Parliament is sitting. Follow every vote."
        today = date(2026, 5, 15)  # A Friday
        
        # Case 1: Today is a sitting day
        sitting_days = {"2026-05-15"}
        warning = MODULE.check_sitting_claim(text, today, sitting_days)
        self.assertIsNone(warning)

        # Case 2: Today is not sitting, but tomorrow is (e.g. Sunday before a sitting week)
        sitting_days = {"2026-05-18"} # Next Monday
        today = date(2026, 5, 17) # Sunday
        warning = MODULE.check_sitting_claim(text, today, sitting_days)
        self.assertIsNone(warning)

        # Case 3: Today is not sitting, and no sitting days within +/- 3 days
        sitting_days = {"2026-06-01"} # Far away
        today = date(2026, 5, 15)
        warning = MODULE.check_sitting_claim(text, today, sitting_days)
        self.assertIn("claims Parliament is sitting, but no chamber meetings found", warning)

    def test_build_report_includes_sitting_warning(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "promotional_text.txt"
            temp_path.write_text("Parliament is sitting.", encoding="utf-8")
            date_path = Path(temp_dir) / "promotional_text_refreshed_at.txt"
            date_path.write_text("2026-05-01", encoding="utf-8")

            # Mock fetch_sitting_days to return no sitting days near the test date
            original_fetch = MODULE.fetch_sitting_days
            MODULE.fetch_sitting_days = lambda year: {"2026-12-25"}
            try:
                report = MODULE.build_report(temp_path, date(2026, 5, 15))
            finally:
                MODULE.fetch_sitting_days = original_fetch

        self.assertTrue(report.is_stale)
        self.assertIn("claims Parliament is sitting", report.warnings[0])
        self.assertFalse(report.is_sitting_confirmed)


if __name__ == "__main__":
    unittest.main()
