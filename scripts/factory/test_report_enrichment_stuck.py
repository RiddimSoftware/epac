import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "factory"))

import report_enrichment_stuck


class ReportEnrichmentStuckTests(unittest.TestCase):
    def test_build_stuck_comment_names_issue_run_and_unblock_action(self) -> None:
        comment = report_enrichment_stuck.build_stuck_comment(
            gh_issue=42,
            run_url="https://github.com/RiddimSoftware/epac/actions/runs/99",
            reason="timeout",
        )

        self.assertIn("Enrichment stuck for GH issue #42", comment)
        self.assertIn("https://github.com/RiddimSoftware/epac/actions/runs/99", comment)
        self.assertIn("operator should inspect the Opus run", comment)

    def test_append_checklist_item_is_idempotent_under_discovered_blockers(self) -> None:
        body = """# Human Handoff

## Discovered blockers
- [ ] Existing manual task

## Notes
Keep this issue open.
"""
        item = "- [ ] EPAC-1966: Opus enrichment timed out for GH issue #42; operator should inspect the run."

        first = report_enrichment_stuck.append_checklist_item(body, item)
        second = report_enrichment_stuck.append_checklist_item(first, item)

        self.assertIn(item, first)
        self.assertEqual(second.count(item), 1)
        self.assertLess(first.index(item), first.index("## Notes"))

    def test_append_checklist_item_adds_section_when_missing(self) -> None:
        item = "- [ ] EPAC-1966: First Opus enrichment run reviewed by operator for quality."

        updated = report_enrichment_stuck.append_checklist_item("# Human Handoff\n", item)

        self.assertIn("## Discovered blockers", updated)
        self.assertIn(item, updated)

    def test_handoff_item_uses_custom_checklist_text_when_supplied(self) -> None:
        class Args:
            checklist_item = "- [ ] First Opus enrichment run reviewed by operator for quality"
            issue_id = "EPAC-1966"
            reason = "timeout"
            gh_issue = 42
            run_url = "https://github.com/RiddimSoftware/epac/actions/runs/99"

        self.assertEqual(
            report_enrichment_stuck.handoff_item(Args()),
            "- [ ] First Opus enrichment run reviewed by operator for quality",
        )


if __name__ == "__main__":
    unittest.main()
