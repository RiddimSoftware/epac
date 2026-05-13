#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parent / "openclaw_release_decision.py"
POLICY_PATH = Path(__file__).parents[2] / "docs/release/openclaw/release-decision-policy.json"


class OpenClawDecisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = {}
        exec(compile(SCRIPT.read_text(), SCRIPT, "exec"), cls.module)  # noqa: S102
        cls.policy = json.loads(POLICY_PATH.read_text())

    def base_state(self):
        return {
            "candidateVersion": "1.4.2",
            "candidateBuild": "20260512.1",
            "action": "app_store_submit_for_review",
            "evaluatedAt": "2026-05-12T20:00:00Z",
            "sourceOfTruth": "app_store_connect_app_store_version",
            "previousVersion": "1.4.1",
            "previousState": "READY_FOR_SALE",
            "previousStateChangedAt": "2026-05-11T19:00:00Z",
            "riskSignals": [],
        }

    def evaluate(self, state):
        return self.module["evaluate"](self.policy, state)

    def test_allows_submission_after_twenty_four_hour_gate(self):
        decision = self.evaluate(self.base_state())
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.rule, "24_hour_gate:elapsed")
        self.assertEqual(decision.elapsed_hours, 25.0)

    def test_waits_when_previous_terminal_state_is_too_recent(self):
        state = self.base_state()
        state["previousStateChangedAt"] = "2026-05-12T04:30:00Z"
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "wait")
        self.assertEqual(decision.rule, "24_hour_gate:not_elapsed")
        self.assertEqual(decision.elapsed_hours, 15.5)

    def test_blocks_when_previous_state_is_not_terminal(self):
        state = self.base_state()
        state["previousState"] = "IN_REVIEW"
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "block")
        self.assertEqual(decision.rule, "24_hour_gate:previous_state_not_terminal")

    def test_testflight_upload_does_not_require_twenty_four_hour_gate(self):
        state = self.base_state()
        state["action"] = "testflight_upload"
        state.pop("previousStateChangedAt")
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.rule, "action:testflight_upload:default")

    def test_phased_release_continuation_requests_approval(self):
        state = self.base_state()
        state["action"] = "phased_release_continue"
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "request_approval")
        self.assertEqual(decision.rule, "action:phased_release_continue:default")

    def test_emergency_hotfix_can_bypass_with_complete_override(self):
        state = self.base_state()
        state["action"] = "emergency_hotfix_release"
        state["previousStateChangedAt"] = "2026-05-12T18:00:00Z"
        state["override"] = {
            "approvedBy": "release-owner@example.com",
            "approvedAt": "2026-05-12T19:55:00Z",
            "reason": "Critical crash fix for production users.",
            "candidateVersion": "1.4.2",
            "candidateBuild": "20260512.1",
            "publicAuditNote": "Emergency release approved for production crash mitigation.",
        }
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.rule, "24_hour_gate:emergency_override")

    def test_invalid_override_blocks(self):
        state = self.base_state()
        state["previousStateChangedAt"] = "2026-05-12T18:00:00Z"
        state["override"] = {"approvedBy": "release-owner@example.com"}
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "block")
        self.assertEqual(decision.rule, "24_hour_gate:invalid_override")

    def test_crash_risk_escalates_even_after_gate_elapsed(self):
        state = self.base_state()
        state["riskSignals"] = ["crash"]
        decision = self.evaluate(state)
        self.assertEqual(decision.decision, "escalate")
        self.assertEqual(decision.rule, "risk_signal:crash")


if __name__ == "__main__":
    unittest.main()
