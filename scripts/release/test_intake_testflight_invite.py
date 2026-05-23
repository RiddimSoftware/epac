#!/usr/bin/env python3
"""
Unit tests for find_prs_since_previous_tf_build.py and extract_reporter_emails.py.

Run with:
  pytest scripts/release/test_intake_testflight_invite.py -v
"""
import json
import re
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

SCRIPTS_DIR = Path(__file__).parent

# ── helpers to load scripts without executing their main() ────────────────────

def _load_script(name: str) -> types.ModuleType:
    mod = types.ModuleType(name)
    script = SCRIPTS_DIR / name
    with open(script) as f:
        exec(compile(f.read(), script, "exec"), mod.__dict__)  # noqa: S102
    return mod


FIND = _load_script("find_prs_since_previous_tf_build.py")
EXTRACT = _load_script("extract_reporter_emails.py")


# ── find_prs_since_previous_tf_build tests ────────────────────────────────────

class TestGetPrNumbersInRange(unittest.TestCase):

    def test_extracts_pr_numbers_from_merge_log(self):
        fake_log = (
            "abc1234 Add reporter intake flow (#42)\n"
            "def5678 Fix session expiry bug (#43)\n"
        )
        with patch.object(FIND, "git", return_value=fake_log):
            result = FIND.get_pr_numbers_in_range("base_sha", "head_sha")
        self.assertEqual(result, ["42", "43"])

    def test_returns_empty_when_no_merges(self):
        with patch.object(FIND, "git", return_value=""):
            result = FIND.get_pr_numbers_in_range("base_sha", "head_sha")
        self.assertEqual(result, [])

    def test_uses_limited_log_when_no_base_sha(self):
        captured = {}

        def fake_git(*args):
            captured["args"] = args
            return ""

        with patch.object(FIND, "git", side_effect=fake_git):
            FIND.get_pr_numbers_in_range(None, "head_sha")

        self.assertIn("-30", captured["args"])

    def test_uses_range_when_base_sha_given(self):
        captured = {}

        def fake_git(*args):
            captured["args"] = args
            return ""

        with patch.object(FIND, "git", side_effect=fake_git):
            FIND.get_pr_numbers_in_range("abc", "def")

        self.assertIn("abc..def", captured["args"])

    def test_ignores_lines_without_pr_number(self):
        fake_log = (
            "abc1234 Regular commit message without PR\n"
            "def5678 Fix critical bug (#99)\n"
        )
        with patch.object(FIND, "git", return_value=fake_log):
            result = FIND.get_pr_numbers_in_range("base", "head")
        self.assertEqual(result, ["99"])


class TestGetPreviousSuccessfulHeadSha(unittest.TestCase):

    def _make_workflows_response(self, workflow_id: int) -> str:
        return json.dumps({
            "workflows": [
                {"id": workflow_id, "name": "TestFlight Build"},
            ]
        })

    def _make_runs_response(self, runs: list[dict]) -> str:
        return json.dumps({"workflow_runs": runs})

    def test_returns_sha_of_most_recent_prior_successful_run(self):
        workflow_response = self._make_workflows_response(123)
        runs_response = self._make_runs_response([
            {"id": 999, "head_sha": "current_sha"},
            {"id": 888, "head_sha": "previous_sha"},
        ])

        responses = iter([workflow_response, runs_response])

        with patch.object(FIND, "gh_api", side_effect=lambda *a, **kw: next(responses)):
            result = FIND.get_previous_successful_head_sha("org/repo", "999")

        self.assertEqual(result, "previous_sha")

    def test_skips_current_run_id(self):
        workflow_response = self._make_workflows_response(123)
        runs_response = self._make_runs_response([
            {"id": 999, "head_sha": "current_sha"},
            {"id": 888, "head_sha": "older_sha"},
        ])

        responses = iter([workflow_response, runs_response])
        with patch.object(FIND, "gh_api", side_effect=lambda *a, **kw: next(responses)):
            result = FIND.get_previous_successful_head_sha("org/repo", "999")

        self.assertEqual(result, "older_sha")

    def test_returns_none_when_no_prior_runs(self):
        workflow_response = self._make_workflows_response(123)
        runs_response = self._make_runs_response([
            {"id": 999, "head_sha": "current_sha"},
        ])

        responses = iter([workflow_response, runs_response])
        with patch.object(FIND, "gh_api", side_effect=lambda *a, **kw: next(responses)):
            result = FIND.get_previous_successful_head_sha("org/repo", "999")

        self.assertIsNone(result)

    def test_returns_none_when_workflow_not_found(self):
        no_match_response = json.dumps({
            "workflows": [{"id": 1, "name": "Some Other Workflow"}]
        })
        runs_response = json.dumps({"workflow_runs": []})

        responses = iter([no_match_response, runs_response])
        with patch.object(FIND, "gh_api", side_effect=lambda *a, **kw: next(responses)):
            result = FIND.get_previous_successful_head_sha("org/repo", "1")

        self.assertIsNone(result)


# ── extract_reporter_emails tests ─────────────────────────────────────────────

class TestExtractEmailsFromBody(unittest.TestCase):

    def test_single_marker(self):
        body = "Some PR description\nReporter-Email: jane@example.com\nMore text"
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, ["jane@example.com"])

    def test_multiple_markers(self):
        body = "Reporter-Email: a@example.com\nReporter-Email: b@example.com"
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, ["a@example.com", "b@example.com"])

    def test_case_insensitive(self):
        body = "reporter-email: lower@example.com\nREPORTER-EMAIL: upper@example.com"
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, ["lower@example.com", "upper@example.com"])

    def test_no_marker_returns_empty(self):
        body = "A normal PR with no reporter marker."
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, [])

    def test_ignores_line_without_at_sign(self):
        body = "Reporter-Email: not-an-email\nReporter-Email: real@example.com"
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, ["real@example.com"])

    def test_empty_body(self):
        result = EXTRACT.extract_emails_from_body("")
        self.assertEqual(result, [])

    def test_trailing_whitespace_stripped(self):
        body = "Reporter-Email: trailing@example.com   \n"
        result = EXTRACT.extract_emails_from_body(body)
        self.assertEqual(result, ["trailing@example.com"])


class TestMainDeduplication(unittest.TestCase):

    def _run_main_with_bodies(self, pr_to_body: dict[str, str]) -> tuple[str, str]:
        """
        Run extract_reporter_emails main() with mocked gh and GITHUB_OUTPUT.
        Returns (emails_value, entries_json).
        """
        outputs: dict[str, str] = {}

        def fake_gh_pr_body(pr_num: str) -> str:
            return pr_to_body.get(pr_num, "")

        def fake_set_output(name: str, value: str) -> None:
            outputs[name] = value

        import io
        from contextlib import redirect_stderr

        with patch.object(EXTRACT, "gh_pr_body", side_effect=fake_gh_pr_body), \
             patch.object(EXTRACT, "set_github_output", side_effect=fake_set_output), \
             patch("sys.argv", ["extract_reporter_emails.py", "--prs", " ".join(pr_to_body.keys())]):
            with redirect_stderr(io.StringIO()):
                EXTRACT.main()

        return outputs.get("emails", ""), outputs.get("entries", "[]")

    def test_deduplicates_same_email_across_prs(self):
        emails_out, entries_json = self._run_main_with_bodies({
            "1": "Reporter-Email: dup@example.com",
            "2": "Reporter-Email: dup@example.com",
        })
        entries = json.loads(entries_json)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["email"], "dup@example.com")
        self.assertEqual(entries[0]["issue"], "1")  # first PR wins

    def test_unique_emails_from_different_prs(self):
        emails_out, entries_json = self._run_main_with_bodies({
            "10": "Reporter-Email: alice@example.com",
            "11": "Reporter-Email: bob@example.com",
        })
        entries = json.loads(entries_json)
        email_set = {e["email"] for e in entries}
        self.assertEqual(email_set, {"alice@example.com", "bob@example.com"})

    def test_no_reporters_yields_empty_outputs(self):
        emails_out, entries_json = self._run_main_with_bodies({
            "99": "No reporter marker here.",
        })
        self.assertEqual(emails_out, "")
        entries = json.loads(entries_json)
        self.assertEqual(entries, [])

    def test_empty_pr_list(self):
        outputs: dict[str, str] = {}

        def fake_set_output(name: str, value: str) -> None:
            outputs[name] = value

        import io
        from contextlib import redirect_stderr

        with patch.object(EXTRACT, "set_github_output", side_effect=fake_set_output), \
             patch("sys.argv", ["extract_reporter_emails.py", "--prs", ""]):
            with redirect_stderr(io.StringIO()):
                EXTRACT.main()

        self.assertEqual(outputs.get("emails", ""), "")
        self.assertEqual(json.loads(outputs.get("entries", "[]")), [])

    def test_multiple_markers_in_single_pr(self):
        body = "Reporter-Email: a@example.com\nReporter-Email: b@example.com"
        emails_out, entries_json = self._run_main_with_bodies({"5": body})
        entries = json.loads(entries_json)
        self.assertEqual(len(entries), 2)


if __name__ == "__main__":
    unittest.main()
