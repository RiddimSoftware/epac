import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "intake" / "start_bugfix_intake.sh"


class StartBugfixIntakeTests(unittest.TestCase):
    def test_launcher_starts_interactive_claude_with_intake_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_claude = root / "claude"
            args_path = root / "args.txt"
            fake_claude.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$@\" > \"$FAKE_CLAUDE_ARGS\"\n",
                encoding="utf-8",
            )
            fake_claude.chmod(0o755)
            env = os.environ.copy()
            env["CLAUDE_BIN"] = str(fake_claude)
            env["FAKE_CLAUDE_ARGS"] = str(args_path)

            result = subprocess.run(
                [str(SCRIPT)],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            args = args_path.read_text(encoding="utf-8")
            self.assertIn("--name", args)
            self.assertIn("epac-bug-report", args)
            self.assertIn("Start epac bug report intake", args)
            self.assertIn("1. File a bug report", args)
            self.assertIn("Do not implement code during intake", args)


if __name__ == "__main__":
    unittest.main()
