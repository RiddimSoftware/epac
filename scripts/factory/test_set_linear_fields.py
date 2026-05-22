#!/usr/bin/env python3
"""Unit tests for set_linear_fields.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).parent / "set_linear_fields.py"
spec = importlib.util.spec_from_file_location("set_linear_fields", SCRIPT)
MODULE = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = MODULE
spec.loader.exec_module(MODULE)


class SetLinearFieldsTests(unittest.TestCase):
    def test_builds_issue_update_payload_with_estimate_and_priority(self) -> None:
        payload = MODULE.build_issue_update_payload("lin_123", 16, 3)

        self.assertEqual(
            payload["variables"],
            {"id": "lin_123", "input": {"estimate": 16, "priority": 3}},
        )
        self.assertIn("issueUpdate", payload["query"])

    def test_rejects_estimates_outside_linear_ladder(self) -> None:
        with self.assertRaises(ValueError) as cm:
            MODULE.validate_linear_fields(32, 3)

        self.assertIn("estimate", str(cm.exception))

    def test_rejects_priority_outside_linear_range(self) -> None:
        with self.assertRaises(ValueError) as cm:
            MODULE.validate_linear_fields(16, 9)

        self.assertIn("priority", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
