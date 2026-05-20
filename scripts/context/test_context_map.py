import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.context import context_map


REPO_ROOT = Path(__file__).resolve().parents[2]


class ContextMapTests(unittest.TestCase):
    def test_build_map_records_metadata_and_entities(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "repo-map.json"

            repo_map = context_map.build_repo_map(REPO_ROOT, out_path)

            self.assertEqual(repo_map["schemaVersion"], 1)
            self.assertEqual(out_path.read_text(), json.dumps(repo_map, indent=2, sort_keys=True) + "\n")

        files_by_path = {entry["path"]: entry for entry in repo_map["files"]}
        self.assertIn("docs/factory/bugfix-intake.md", files_by_path)
        self.assertIn("scripts/intake/bugfix_spec.py", files_by_path)
        self.assertIn(".github/workflows/backend-tests.yml", files_by_path)
        self.assertNotIn("app-store/in-app-events/landscape-en-CA.png", files_by_path)

        bugfix_doc = files_by_path["docs/factory/bugfix-intake.md"]
        self.assertEqual(bugfix_doc["extension"], ".md")
        self.assertEqual(bugfix_doc["category"], "docs")
        self.assertGreater(bugfix_doc["lineCount"], 10)
        self.assertIn("Bugfix Intake Harness", bugfix_doc["headings"])
        self.assertIn("Bugfix Intake Harness", bugfix_doc["entities"])

        intake_script = files_by_path["scripts/intake/bugfix_spec.py"]
        self.assertEqual(intake_script["category"], "python")
        self.assertIn("build_input", intake_script["entities"])
        self.assertIn("validate_spec", intake_script["entities"])

        workflow = files_by_path[".github/workflows/backend-tests.yml"]
        self.assertEqual(workflow["category"], "github-workflow")
        self.assertTrue(any(entity.startswith("workflow:") for entity in workflow["entities"]))
        self.assertTrue(any(entity.startswith("job:") for entity in workflow["entities"]))

    def test_search_ranks_by_query_overlap_and_explains_matches(self):
        repo_map = {
            "schemaVersion": 1,
            "files": [
                {
                    "path": "ios/epac/Views/HomeView.swift",
                    "extension": ".swift",
                    "category": "swift",
                    "lineCount": 20,
                    "sizeBytes": 400,
                    "headings": [],
                    "entities": ["HomeStatusCard", "LiveDataBadge"],
                },
                {
                    "path": "backend/live-status/main.go",
                    "extension": ".go",
                    "category": "go",
                    "lineCount": 30,
                    "sizeBytes": 500,
                    "headings": [],
                    "entities": ["LiveStatus"],
                },
            ],
        }

        results = context_map.search_repo_map(repo_map, "home status card live data")

        self.assertEqual(results[0]["path"], "ios/epac/Views/HomeView.swift")
        self.assertGreater(results[0]["score"], results[1]["score"])
        self.assertIn("path:home", results[0]["why"])
        self.assertIn("entities:HomeStatusCard", results[0]["why"])
        self.assertIn("entities:LiveDataBadge", results[0]["why"])

    def test_cli_build_and_search(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "repo-map.json"
            build = subprocess.run(
                [sys.executable, "scripts/context/context_map.py", "build", "--out", str(out_path)],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            self.assertTrue(out_path.exists())

            search = subprocess.run(
                [
                    sys.executable,
                    "scripts/context/context_map.py",
                    "search",
                    "--map",
                    str(out_path),
                    "--query",
                    "home status card live data",
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(search.returncode, 0, search.stderr)
            self.assertIn("Top matches for: home status card live data", search.stdout)
            self.assertIn("why:", search.stdout)


if __name__ == "__main__":
    unittest.main()
