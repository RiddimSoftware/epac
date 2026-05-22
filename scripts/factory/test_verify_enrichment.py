import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "factory"))

import verify_enrichment


INTAKE_BODY = """<!--
Intake-Session: 7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1
Reporter-Email: reporter@example.com
Reporter-GitHub: octocat
Source: science-fair-2026-05-28
Mode: bug
Estimate: 8
Cost-Estimate-USD: pending
-->

## Observed behaviour
The app opens the wrong bill.

Linear ticket: https://linear.app/riddimsoftware/issue/EPAC-123/fix-bill-routing
"""


class VerifyEnrichmentTests(unittest.TestCase):
    def test_parse_intake_markers_reads_contract_block(self) -> None:
        markers = verify_enrichment.parse_intake_markers(INTAKE_BODY)

        self.assertEqual(markers["Intake-Session"], "7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1")
        self.assertEqual(markers["Reporter-Email"], "reporter@example.com")
        self.assertEqual(markers["Mode"], "bug")
        self.assertEqual(markers["Estimate"], "8")

    def test_extract_linear_identifier_from_issue_body_or_comments(self) -> None:
        self.assertEqual(verify_enrichment.extract_linear_identifier(INTAKE_BODY, []), "EPAC-123")

        comments = [
            "Created Linear ticket: https://linear.app/riddimsoftware/issue/EPAC-456/triage-this",
        ]
        self.assertEqual(verify_enrichment.extract_linear_identifier("no link here", comments), "EPAC-456")

    def test_validate_linear_state_accepts_ready_enriched_bug(self) -> None:
        markers = verify_enrichment.parse_intake_markers(INTAKE_BODY)
        linear_body = """<!--
Intake-Session: 7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1
Reporter-Email: reporter@example.com
Reporter-GitHub: octocat
Source: science-fair-2026-05-28
Mode: bug
Estimate: 8
Cost-Estimate-USD: pending
-->

## Problem
The current navigation target is stale.

## Root Cause Analysis
The selection model reuses the previous bill identifier.

## Acceptance Criteria
- Given a bill is selected When detail opens Then the selected bill appears.

## Evidence Plan
Add before/after navigation screenshots.

## Validation Plan
Reporter validates the TestFlight build.
"""

        errors = verify_enrichment.validate_linear_state(
            body=linear_body,
            markers=markers,
            mode="bug",
            labels=["intake/bug", "intake/ready"],
            estimate=8.0,
            priority=2,
        )

        self.assertEqual(errors, [])

    def test_validate_linear_state_rejects_missing_markers_and_old_label(self) -> None:
        markers = verify_enrichment.parse_intake_markers(INTAKE_BODY)

        errors = verify_enrichment.validate_linear_state(
            body="## Problem\nToo short.",
            markers=markers,
            mode="bug",
            labels=["intake/needs-enrichment"],
            estimate=None,
            priority=0,
        )

        self.assertIn("Linear body is missing marker: Intake-Session", errors)
        self.assertIn("Linear issue still has intake/needs-enrichment label", errors)
        self.assertIn("Linear issue is missing intake/ready label", errors)
        self.assertIn("Linear issue estimate is not set", errors)
        self.assertIn("Linear issue priority is not set", errors)

    def test_validate_feature_spec_text_accepts_stage_two_structure(self) -> None:
        spec = """# Feature SPEC: Add saved debate shortcuts

Trace ID: FEATURE-20260522-123456
Reporter: reporter@example.com
Source: GitHub issue #12
Created at: 2026-05-22T12:34:56Z
Target repo: RiddimSoftware/epac
Affected surface: Member profile

## Feature Description
Add a quick action that saves a debate from the member profile.

## Use Case
Readers want to revisit relevant debate participation later.

## Acceptance Criteria
- Given a member profile is open
  When the reader saves a debate
  Then the debate appears in saved items.
- Given saved items are visible
  When the reader opens the saved debate
  Then it opens the original debate context.

## Evidence Plan
Before and after screenshots of the save action and saved-item destination.

## Validation Plan
Reporter validates the TestFlight build and confirms the saved item works.

## Non-goals
Do not add sync or account-based saved items.

## Provenance
- Intake kind: feature
- Intake-Session: 7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1
- Reporter-Email: reporter@example.com

## Next Steps
- Link the implementation PR back to this SPEC.
"""

        self.assertEqual(verify_enrichment.validate_feature_spec_text(spec, mode="feature"), [])

    def test_spec_path_uses_intake_session_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = "7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1"

            self.assertEqual(
                verify_enrichment.spec_path_for_session(root, session),
                root / ".factory" / "intake" / session / "SPEC.md",
            )


if __name__ == "__main__":
    unittest.main()
