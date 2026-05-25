import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "intake" / "bugfix_spec.py"


class BugfixSpecCLITests(unittest.TestCase):
    def run_new_spec(
        self,
        estimate: int = 8,
        tmpdir: Path | None = None,
        overrides: list[str] | None = None,
    ) -> Path:
        if tmpdir is None:
            raise ValueError("tmpdir is required in tests so output is automatically cleaned up")
        output = Path(tmpdir)
        spec_path = output / "SPEC.md"
        args = [
            "new",
            "--title",
            "Home screen implies live debate data",
            "--reporter",
            "demo-reporter",
            "--source",
            "llm-session",
            "--surface",
            "Home status card",
            "--observed",
            "The card says cached live data even when only archived debates are available.",
            "--expected",
            "The card explains that epac currently shows past debates and archival data.",
            "--estimate",
            str(estimate),
            "--step",
            "Launch epac.",
            "--step",
            "Open the Home tab.",
            "--evidence",
            "before/after screenshot of the Home status card",
            "--validation",
            "Reporter confirms the TestFlight build no longer implies live data.",
            "--out",
            str(spec_path),
        ]
        if overrides:
            args.extend(overrides)
        result = self.run_cli(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return spec_path

    def run_cli(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=cwd or ROOT,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_new_writes_valid_spec(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = self.run_new_spec(tmpdir=tmp)
            contents = output.read_text()
            self.assertIn("# Bugfix SPEC: Home screen implies live debate data", contents)
            self.assertIn("Trace ID:", contents)
            self.assertIn("Reporter: demo-reporter", contents)
            self.assertIn("Estimate: 8", contents)
            self.assertIn("Given the Home status card is visible", contents)

            validate = self.run_cli("validate", str(output))
            self.assertEqual(validate.returncode, 0, validate.stderr)
            self.assertIn("valid bugfix SPEC", validate.stdout)
            receipt = output.with_name("receipt.json")
            self.assertTrue(receipt.exists())
            data = json.loads(receipt.read_text())
            self.assertEqual(data["schemaVersion"], 1)
            self.assertEqual(data["kind"], "bugfix_spec_created")
            self.assertEqual(data["terminalState"], "spec_valid")
            self.assertEqual(data["repo"], "RiddimSoftware/epac")
            self.assertEqual(data["specPath"], str(output))
            self.assertTrue(data["traceId"].startswith("BUGFIX-"))
            self.assertEqual(data["reporter"], "demo-reporter")
            self.assertEqual(data["source"], "llm-session")
            self.assertEqual(data["affectedSurface"], "Home status card")

    def test_new_receipt_includes_session_and_source_tool_when_supplied(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = self.run_new_spec(
                tmpdir=tmp,
                overrides=[
                    "--source-tool",
                    "claude",
                    "--session-id",
                    "sess-demo",
                ],
            )
            data = json.loads(output.with_name("receipt.json").read_text())
            self.assertEqual(data["sourceTool"], "claude")
            self.assertEqual(data["sessionId"], "sess-demo")

    def test_validate_rejects_incomplete_spec(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            spec = Path(tmp) / "SPEC.md"
            spec.write_text("# Bugfix SPEC: Missing details\n\n## Problem\nToo vague.\n")

            result = self.run_cli("validate", str(spec))

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required section", result.stderr)

    def test_new_rejects_invalid_estimate_values(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "SPEC.md"
            result = self.run_cli(
                "new",
                "--title",
                "Home screen implies live debate data",
                "--reporter",
                "demo-reporter",
                "--source",
                "llm-session",
                "--surface",
                "Home status card",
                "--observed",
                "The card says cached live data even when only archived debates are available.",
                "--expected",
                "The card explains that epac currently shows past debates and archival data.",
                "--estimate",
                "3",
                "--step",
                "Launch epac.",
                "--step",
                "Open the Home tab.",
                "--evidence",
                "before/after screenshot of the Home status card",
                "--validation",
                "Reporter confirms the TestFlight build no longer implies live data.",
                "--out",
                str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("--estimate must be one of", result.stderr)

    def test_validate_rejects_missing_or_off_ladder_estimate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = self.run_new_spec(tmpdir=tmp)
            missing = output.read_text().replace("- Estimate: 8", "")
            missing_output = Path(tmp) / "missing.md"
            missing_output.write_text(missing)

            missing_result = self.run_cli("validate", str(missing_output))
            self.assertNotEqual(missing_result.returncode, 0)
            self.assertIn("missing required effort estimate field: Estimate", missing_result.stderr)

            off_ladder = output.read_text().replace("- Estimate: 8", "- Estimate: 10")
            off_ladder_output = Path(tmp) / "off-ladder.md"
            off_ladder_output.write_text(off_ladder)

            off_ladder_result = self.run_cli("validate", str(off_ladder_output))
            self.assertNotEqual(off_ladder_result.returncode, 0)
            self.assertIn("invalid effort estimate", off_ladder_result.stderr)

    def test_new_accepts_each_valid_estimate_value(self) -> None:
        for estimate in (1, 2, 4, 8, 16, 32, 64):
            with tempfile.TemporaryDirectory() as tmp:
                output = Path(tmp) / "SPEC.md"
                result = self.run_cli(
                    "new",
                    "--title",
                    "Home screen implies live debate data",
                    "--reporter",
                    "demo-reporter",
                    "--source",
                    "llm-session",
                    "--surface",
                    "Home status card",
                    "--observed",
                    "The card says cached live data even when only archived debates are available.",
                    "--expected",
                    "The card explains that epac currently shows past debates and archival data.",
                    "--estimate",
                    str(estimate),
                    "--step",
                    "Launch epac.",
                    "--step",
                    "Open the Home tab.",
                    "--evidence",
                    "before/after screenshot of the Home status card",
                    "--validation",
                    "Reporter confirms the TestFlight build no longer implies live data.",
                    "--out",
                    str(output),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"Estimate: {estimate}", output.read_text())
                validate = self.run_cli("validate", str(output))
                self.assertEqual(validate.returncode, 0, validate.stderr)

    def test_issue_body_renders_from_valid_spec(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = self.run_new_spec(
                tmpdir=tmp,
                overrides=[
                    "--title",
                    "Search result tap opens wrong debate",
                    "--reporter",
                    "octocat",
                    "--source",
                    "github-issue",
                    "--surface",
                    "Search results",
                    "--observed",
                    "Tapping one result opens a different debate.",
                    "--expected",
                    "Tapping a result opens the selected debate.",
                    "--evidence",
                    "Maestro flow video showing search result navigation",
                    "--validation",
                    "Reporter retests the linked TestFlight build.",
                ],
            )

            result = self.run_cli("issue-body", str(output))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("## Bugfix intake receipt", result.stdout)
            self.assertIn("Search result tap opens wrong debate", result.stdout)
            self.assertIn("Spec: ", result.stdout)
            self.assertIn("Evidence plan", result.stdout)


if __name__ == "__main__":
    unittest.main()
