import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "intake" / "intake_session_hook.py"
SETTINGS = ROOT / ".factory" / "hooks" / "claude-settings.example.json"


class IntakeSessionHookTests(unittest.TestCase):
    def run_hook(
        self,
        root: Path,
        subcommand: str,
        payload: dict,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["EPAC_INTAKE_ROOT"] = str(root)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(SCRIPT), subcommand],
            input=json.dumps(payload),
            check=False,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def read_events(self, root: Path, session_id: str) -> list[dict]:
        events_path = root / ".factory" / "intake" / "sessions" / session_id / "events.jsonl"
        return [json.loads(line) for line in events_path.read_text().splitlines()]

    def test_session_start_writes_session_record_with_mode_and_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            start = self.run_hook(
                root,
                "session-start",
                {
                    "session_id": "sess-mode",
                    "cwd": str(root),
                    "transcript_path": "/tmp/codex-session.jsonl",
                },
                {"EPAC_INTAKE_MODE": "feature", "EPAC_INTAKE_AGENT": "codex"},
            )

            self.assertEqual(start.returncode, 0, start.stderr)
            session_path = root / ".factory" / "intake" / "sessions" / "sess-mode" / "session.json"
            session = json.loads(session_path.read_text())
            self.assertEqual(session["session_id"], "sess-mode")
            self.assertEqual(session["mode"], "feature")
            self.assertEqual(session["agent"], "codex")
            self.assertIn("started_at", session)
            self.assertNotIn("ended_at", session)

    def test_user_prompt_submit_appends_transcript_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            first = self.run_hook(root, "user-prompt-submit", {"session_id": "sess-transcript", "prompt": "First message"})
            second = self.run_hook(root, "user-prompt-submit", {"session_id": "sess-transcript", "prompt": "Second message"})

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            transcript = (
                root / ".factory" / "intake" / "sessions" / "sess-transcript" / "transcript.md"
            ).read_text()
            self.assertEqual(transcript.count("```text"), 2)
            self.assertIn("First message", transcript)
            self.assertIn("Second message", transcript)

    def test_post_tool_use_records_gh_issue_create_url(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            tool = self.run_hook(
                root,
                "post-tool-use",
                {
                    "session_id": "sess-issue",
                    "tool_name": "Bash",
                    "tool_input": {"command": "gh issue create --title Bug --body details"},
                    "tool_response": {"stdout": "https://github.com/RiddimSoftware/epac/issues/123\n"},
                },
            )

            self.assertEqual(tool.returncode, 0, tool.stderr)
            issues_path = root / ".factory" / "intake" / "sessions" / "sess-issue" / "issues.jsonl"
            issues = [json.loads(line) for line in issues_path.read_text().splitlines()]
            self.assertEqual(len(issues), 1)
            self.assertEqual(issues[0]["session_id"], "sess-issue")
            self.assertEqual(issues[0]["issue_url"], "https://github.com/RiddimSoftware/epac/issues/123")
            self.assertEqual(issues[0]["toolName"], "Bash")

    def test_captures_prompt_and_tool_events_with_redaction(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            prompt = self.run_hook(
                root,
                "user-prompt-submit",
                {
                    "session_id": "sess-123",
                    "cwd": str(root),
                    "transcript_path": "/tmp/transcript.jsonl",
                    "prompt": "Please fix login. password=hunter2 token=abcdef1234567890abcdef1234567890",
                },
            )
            self.assertEqual(prompt.returncode, 0, prompt.stderr)

            tool = self.run_hook(
                root,
                "post-tool-use",
                {
                    "session_id": "sess-123",
                    "tool_name": "Bash",
                    "tool_input": {"command": "curl -H 'Authorization: Bearer abcdef1234567890abcdef1234567890'"},
                    "tool_response": {"output": "ok", "api_secret": "super-secret"},
                },
            )
            self.assertEqual(tool.returncode, 0, tool.stderr)

            events = self.read_events(root, "sess-123")
            self.assertEqual([event["hookEvent"] for event in events], ["user-prompt-submit", "post-tool-use"])
            self.assertEqual(events[0]["session_id"], "sess-123")
            self.assertEqual(events[0]["cwd"], str(root))
            self.assertEqual(events[0]["transcript_path"], "/tmp/transcript.jsonl")
            self.assertEqual(events[0]["sourceTool"], "claude")
            self.assertIn("Please fix login", events[0]["promptSummary"])
            serialized = json.dumps(events)
            self.assertNotIn("hunter2", serialized)
            self.assertNotIn("abcdef1234567890abcdef1234567890", serialized)
            self.assertNotIn("super-secret", serialized)
            self.assertEqual(events[1]["toolName"], "Bash")
            self.assertIn("command", events[1]["toolInputSummary"])
            self.assertIn("output", events[1]["toolResponseSummary"])

    def test_session_start_records_event_without_bug_report_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            start = self.run_hook(
                root,
                "session-start",
                {
                    "session_id": "sess-start",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                },
            )

            self.assertEqual(start.returncode, 0, start.stderr)
            self.assertEqual(start.stdout, "")
            events = self.read_events(root, "sess-start")
            self.assertEqual(events[0]["hookEvent"], "session-start")

    def test_session_start_then_non_bugfix_prompt_does_not_print_bug_report_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            start = self.run_hook(
                root,
                "session-start",
                {
                    "session_id": "sess-start-normal",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                },
            )
            first = self.run_hook(
                root,
                "user-prompt-submit",
                {
                    "session_id": "sess-start-normal",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                    "prompt": "awefawef",
                },
            )

            self.assertEqual(start.returncode, 0, start.stderr)
            self.assertEqual(start.stdout, "")
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(first.stdout, "")

    def test_first_bugfix_prompt_prints_bug_report_context_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            first = self.run_hook(
                root,
                "user-prompt-submit",
                {
                    "session_id": "sess-first-prompt",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                    "prompt": "bugfix",
                },
            )
            second = self.run_hook(
                root,
                "user-prompt-submit",
                {
                    "session_id": "sess-first-prompt",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                    "prompt": "the affected screen is Settings",
                },
            )

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn("Bug report mode is the default", first.stdout)
            self.assertIn("Do not implement code during intake", first.stdout)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.stdout, "")

    def test_first_non_bugfix_prompt_does_not_print_bug_report_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            first = self.run_hook(
                root,
                "user-prompt-submit",
                {
                    "session_id": "sess-normal-prompt",
                    "cwd": str(root),
                    "transcript_path": "/tmp/claude-session.jsonl",
                    "prompt": "awefawe",
                },
            )

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(first.stdout, "")

    def test_stop_writes_spec_valid_summary_when_receipt_exists(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            intake = root / ".factory" / "intake" / "20260519-demo"
            intake.mkdir(parents=True)
            receipt = {
                "schemaVersion": 1,
                "kind": "bugfix_spec_created",
                "traceId": "BUGFIX-demo",
                "repo": "RiddimSoftware/epac",
                "specPath": str(intake / "SPEC.md"),
                "createdAt": "2026-05-19T00:00:00Z",
                "terminalState": "spec_valid",
            }
            (intake / "receipt.json").write_text(json.dumps(receipt))

            stop = self.run_hook(root, "stop", {"session_id": "sess-stop"})

            self.assertEqual(stop.returncode, 0, stop.stderr)
            summary_path = root / ".factory" / "intake" / "sessions" / "sess-stop" / "summary.json"
            summary = json.loads(summary_path.read_text())
            self.assertEqual(summary["terminalState"], "spec_valid")
            self.assertEqual(summary["receipt"]["traceId"], "BUGFIX-demo")

    def test_stop_writes_unfinished_summary_and_draft_without_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            stop = self.run_hook(
                root,
                "stop",
                {"session_id": "sess-unfinished", "prompt": "App crashes on launch with secret=do-not-store"},
            )

            self.assertEqual(stop.returncode, 0, stop.stderr)
            session_dir = root / ".factory" / "intake" / "sessions" / "sess-unfinished"
            summary = json.loads((session_dir / "summary.json").read_text())
            self.assertEqual(summary["terminalState"], "unfinished_intake")
            self.assertTrue((session_dir / "unfinished-intake.md").exists())
            serialized = json.dumps(summary) + (session_dir / "unfinished-intake.md").read_text()
            self.assertNotIn("do-not-store", serialized)

    def test_stop_finalizes_session_record_and_appends_index_rollup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            start = self.run_hook(
                root,
                "session-start",
                {"session_id": "sess-index"},
                {"EPAC_INTAKE_MODE": "open-data", "EPAC_INTAKE_AGENT": "claude"},
            )
            issue = self.run_hook(
                root,
                "post-tool-use",
                {
                    "session_id": "sess-index",
                    "tool_name": "Bash",
                    "tool_input": {"command": "gh issue create --title Intake"},
                    "tool_response": {"stdout": "Created https://github.com/RiddimSoftware/epac/issues/456"},
                },
            )
            stop = self.run_hook(
                root,
                "stop",
                {"session_id": "sess-index"},
                {"EPAC_INTAKE_MODE": "open-data", "EPAC_INTAKE_AGENT": "claude"},
            )

            self.assertEqual(start.returncode, 0, start.stderr)
            self.assertEqual(issue.returncode, 0, issue.stderr)
            self.assertEqual(stop.returncode, 0, stop.stderr)
            session_path = root / ".factory" / "intake" / "sessions" / "sess-index" / "session.json"
            session = json.loads(session_path.read_text())
            self.assertIn("ended_at", session)
            self.assertIsInstance(session["duration_seconds"], int)

            index_path = root / ".factory" / "intake" / "index.jsonl"
            index = [json.loads(line) for line in index_path.read_text().splitlines()]
            self.assertEqual(len(index), 1)
            self.assertEqual(
                set(index[0]),
                {"session_id", "started_at", "ended_at", "mode", "agent", "issue_urls", "duration_seconds"},
            )
            self.assertEqual(index[0]["session_id"], "sess-index")
            self.assertEqual(index[0]["mode"], "open-data")
            self.assertEqual(index[0]["agent"], "claude")
            self.assertEqual(index[0]["issue_urls"], ["https://github.com/RiddimSoftware/epac/issues/456"])
            self.assertIsInstance(index[0]["duration_seconds"], int)

    def test_claude_settings_example_uses_expected_hook_commands(self) -> None:
        settings = json.loads(SETTINGS.read_text())
        hooks = settings["hooks"]
        self.assertIn("SessionStart", hooks)
        self.assertIn("UserPromptSubmit", hooks)
        self.assertIn("PostToolUse", hooks)
        self.assertIn("Stop", hooks)
        commands = json.dumps(settings)
        self.assertIn("intake_session_hook.py session-start", commands)
        self.assertIn("intake_session_hook.py user-prompt-submit", commands)
        self.assertIn("intake_session_hook.py post-tool-use", commands)
        self.assertIn("intake_session_hook.py stop", commands)


if __name__ == "__main__":
    unittest.main()
