from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DOC_PATH = ROOT / ".factory" / "prompts" / "intake-issue-body.md"


EXAMPLE_BLOCKS = re.compile(
    r"^### Example:\s*(?P<mode>bug|feature|fact-check|open-data)\s*\n(?P<block>.*?)(?=\n^### Example:|\Z)",
    re.MULTILINE | re.DOTALL,
)
MARKER_BLOCK = re.compile(r"^<!--\n(?P<markers>.*?)\n-->\n", re.DOTALL | re.MULTILINE)

MARKER_PATTERNS = {
    "session": re.compile(r"^Intake-Session:\s*([a-f0-9-]{36})$", re.MULTILINE),
    "email": re.compile(r"^Reporter-Email:\s*(\S+@\S+|anonymous)$", re.MULTILINE),
    "github": re.compile(r"^Reporter-GitHub:\s*(.*)$", re.MULTILINE),
    "source": re.compile(r"^Source:\s*(science-fair-2026-05-28|mobile-web|repo-local)$", re.MULTILINE),
    "mode": re.compile(r"^Mode:\s*(bug|feature|fact-check|open-data)$", re.MULTILINE),
    "estimate": re.compile(r"^Estimate:\s*(1|2|4|8|16|32|64)$", re.MULTILINE),
    "cost": re.compile(r"^Cost-Estimate-USD:\s*([\d.]+|pending)$", re.MULTILINE),
}

REQUIRED_BODY_HEADINGS = {
    "bug": {
        "## Observed behaviour",
        "## Expected behaviour",
        "## Reproduction steps",
        "## Acceptance criteria",
        "## Validation plan",
    },
    "feature": {
        "## Feature description",
        "## Use case",
        "## Acceptance criteria",
        "## Validation plan",
    },
    "fact-check": {
        "## Question",
    },
    "open-data": {
        "## Data source",
        "## Use case",
        "## Sample payload",
        "## Acceptance criteria",
        "## Validation plan",
    },
}


class IntakeIssueBodyContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = DOC_PATH.read_text(encoding="utf-8")

    def extract_examples(self) -> dict[str, str]:
        examples = {}
        for match in EXAMPLE_BLOCKS.finditer(self.text):
            mode = match.group("mode").strip()
            block = match.group("block")
            start = block.find("```")
            self.assertNotEqual(start, -1, f"missing fenced example body for {mode}")
            end = block.rfind("```")
            self.assertNotEqual(end, -1, f"missing fenced example body for {mode}")
            self.assertGreater(end, start, f"malformed fenced example body for {mode}")
            body = block[start + 3 : end].strip()
            if body.startswith(("text\n", "markdown\n")):
                _, _, body = body.partition("\n")
                body = body.strip()
            examples[mode] = body
        return examples

    def test_examples_exist(self) -> None:
        examples = self.extract_examples()
        self.assertEqual(set(examples.keys()), {"bug", "feature", "fact-check", "open-data"})

    def test_required_marker_regexes_parse(self) -> None:
        examples = self.extract_examples()
        for mode, body in examples.items():
            self.assertTrue(body.startswith("<!--"), f"marker block missing for {mode}")
            marker_match = MARKER_BLOCK.match(body)
            self.assertIsNotNone(marker_match, f"marker block malformed for {mode}")
            markers = marker_match.group("markers")
            for name, pattern in MARKER_PATTERNS.items():
                self.assertIsNotNone(
                    pattern.search(markers),
                    f"{name} marker did not match required regex in {mode} example",
                )
            # mode-specific guard
            mode_value = MARKER_PATTERNS["mode"].search(markers)
            self.assertIsNotNone(mode_value)
            self.assertEqual(mode_value.group(1), mode)

    def test_mode_specific_headings_present(self) -> None:
        examples = self.extract_examples()
        for mode, body in examples.items():
            headings = REQUIRED_BODY_HEADINGS[mode]
            for heading in headings:
                self.assertIn(heading, body, f"missing heading '{heading}' in {mode} example")


if __name__ == "__main__":
    unittest.main()
