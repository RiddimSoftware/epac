import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "intake" / "bugfix_session_hook.py"
SETTINGS = ROOT / ".factory" / "hooks" / "claude-settings.example.json"


class BugfixSessionHookTests(unittest.TestCase):
    def run_hook(
        self,
        root: Path,
        subcommand: str,
        payload: dict,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["BUGFIX_INTAKE_ROOT"] = str(root)
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

    def test_session_start_prints_default_bug_report_menu(self) -> None:
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
            self.assertIn("Bug report mode is the default", start.stdout)
            self.assertIn("1. File a bug report", start.stdout)
            self.assertIn("2. Exit bug-report mode", start.stdout)
            self.assertIn("python3 scripts/intake/bugfix_spec.py new", start.stdout)
            events = self.read_events(root, "sess-start")
            self.assertEqual(events[0]["hookEvent"], "session-start")

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

    def test_claude_settings_example_uses_expected_hook_commands(self) -> None:
        settings = json.loads(SETTINGS.read_text())
        hooks = settings["hooks"]
        self.assertIn("SessionStart", hooks)
        self.assertIn("UserPromptSubmit", hooks)
        self.assertIn("PostToolUse", hooks)
        self.assertIn("Stop", hooks)
        commands = json.dumps(settings)
        self.assertIn("bugfix_session_hook.py session-start", commands)
        self.assertIn("bugfix_session_hook.py user-prompt-submit", commands)
        self.assertIn("bugfix_session_hook.py post-tool-use", commands)
        self.assertIn("bugfix_session_hook.py stop", commands)


if __name__ == "__main__":
    unittest.main()
