#!/usr/bin/env python3
"""Unit tests for parse_intake_markers.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).parent / "parse_intake_markers.py"
spec = importlib.util.spec_from_file_location("parse_intake_markers", SCRIPT)
MODULE = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = MODULE
spec.loader.exec_module(MODULE)


class ParseIntakeMarkersTests(unittest.TestCase):
    def test_maps_sf_estimate_ladder_to_linear_ladder(self) -> None:
        body = """
        ## Factory markers
        Estimate: 32
        Mode: feature
        Reporter-Email: reporter@example.com
        """

        markers = MODULE.parse_markers(body)

        self.assertEqual(markers.estimate_sf, 32)
        self.assertEqual(markers.estimate_linear, 24)
        self.assertEqual(markers.mode, "feature")
        self.assertEqual(markers.reporter_email, "reporter@example.com")
        self.assertEqual(markers.priority, 4)

    def test_bug_mode_gets_medium_priority_and_identity_estimate(self) -> None:
        body = "Estimate: 16\nMode: bug\nReporter-Email: person@example.com\n"

        markers = MODULE.parse_markers(body)

        self.assertEqual(markers.estimate_linear, 16)
        self.assertEqual(markers.priority, 3)

    def test_missing_required_marker_is_reported_without_exception(self) -> None:
        result = MODULE.parse_body("Estimate: 8\nMode: bug\n")

        self.assertFalse(result.should_sync)
        self.assertIn("Reporter-Email", result.error)

    def test_unknown_estimate_is_reported_without_exception(self) -> None:
        result = MODULE.parse_body(
            "Estimate: 3\nMode: bug\nReporter-Email: person@example.com\n"
        )

        self.assertFalse(result.should_sync)
        self.assertIn("Unsupported Estimate", result.error)


if __name__ == "__main__":
    unittest.main()
