"""Unit tests for pbo_ingest.py — API parsing and mapping."""

from __future__ import annotations

import unittest
from pbo_ingest import _normalize_category, _content_hash, PBOPublication

class CategoryMappingTests(unittest.TestCase):
    def test_legislative_cost(self) -> None:
        self.assertEqual(_normalize_category("LEG", "Title", "Abstract"), "legislative-cost")
        self.assertEqual(_normalize_category("ES", "Title", "Abstract"), "legislative-cost")
        self.assertEqual(_normalize_category("RP", "Legislative Costing of something", "Abstract"), "legislative-cost")

    def test_fiscal_update(self) -> None:
        self.assertEqual(_normalize_category("RP", "Economic and Fiscal Outlook", "Abstract"), "fiscal-update")
        self.assertEqual(_normalize_category("NT", "Fiscal Analysis", "Abstract"), "fiscal-update")
        self.assertEqual(_normalize_category("OA", "Fiscal Update", "Abstract"), "fiscal-update")
        self.assertEqual(_normalize_category("RP", "Main Estimates", "Abstract"), "fiscal-update")
        self.assertEqual(_normalize_category("RP", "Title", "Fiscal track info"), "fiscal-update")

    def test_election_platform(self) -> None:
        self.assertEqual(_normalize_category("RP", "Election Platform Costing", "Abstract"), "election-platform")
        self.assertEqual(_normalize_category("RP", "Election Platform", "Abstract"), "election-platform")

    def test_program_evaluation(self) -> None:
        self.assertEqual(_normalize_category("RP", "Program Evaluation", "Abstract"), "program-evaluation")
        self.assertEqual(_normalize_category("RP", "Program Assessment", "Abstract"), "program-evaluation")

    def test_fallback(self) -> None:
        self.assertEqual(_normalize_category("RP", "Something Else", "Abstract"), "other")
        self.assertEqual(_normalize_category("", "Title", "Abstract"), None)

class ContentHashTests(unittest.TestCase):
    def test_consistent_hash(self) -> None:
        h1 = _content_hash("Title", "2024-01-01")
        h2 = _content_hash("Title", "2024-01-01")
        self.assertEqual(h1, h2)

    def test_different_hash(self) -> None:
        h1 = _content_hash("Title 1", "2024-01-01")
        h2 = _content_hash("Title 2", "2024-01-01")
        self.assertNotEqual(h1, h2)

if __name__ == "__main__":
    unittest.main()
