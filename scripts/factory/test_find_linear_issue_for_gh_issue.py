#!/usr/bin/env python3
"""Unit tests for find_linear_issue_for_gh_issue.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).parent / "find_linear_issue_for_gh_issue.py"
spec = importlib.util.spec_from_file_location("find_linear_issue_for_gh_issue", SCRIPT)
MODULE = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = MODULE
spec.loader.exec_module(MODULE)


class FindLinearIssueForGhIssueTests(unittest.TestCase):
    def test_builds_canonical_github_issue_url(self) -> None:
        self.assertEqual(
            MODULE.github_issue_url("RiddimSoftware/epac", 42),
            "https://github.com/RiddimSoftware/epac/issues/42",
        )

    def test_polls_until_attachment_resolves_issue_id(self) -> None:
        calls: list[str] = []

        def fake_query(url: str, api_key: str) -> str | None:
            calls.append(url)
            if len(calls) < 3:
                return None
            return "lin_123"

        issue_id = MODULE.wait_for_linear_issue(
            "RiddimSoftware/epac",
            42,
            "test-key",
            query_issue_id=fake_query,
            timeout_seconds=60,
            interval_seconds=0,
        )

        self.assertEqual(issue_id, "lin_123")
        self.assertEqual(calls, ["https://github.com/RiddimSoftware/epac/issues/42"] * 3)

    def test_timeout_raises_clear_error(self) -> None:
        with self.assertRaises(TimeoutError) as cm:
            MODULE.wait_for_linear_issue(
                "RiddimSoftware/epac",
                42,
                "test-key",
                query_issue_id=lambda url, api_key: None,
                timeout_seconds=0,
                interval_seconds=0,
            )

        self.assertIn("Timed out waiting", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
