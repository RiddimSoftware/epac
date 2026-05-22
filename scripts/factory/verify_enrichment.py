#!/usr/bin/env python3
"""Verify that Stage-2 intake enrichment completed."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
LINEAR_URL_RE = re.compile(r"https://linear\.app/[^\s)]+/issue/([A-Z]+-\d+)[^\s)]*", re.IGNORECASE)
LINEAR_IDENTIFIER_RE = re.compile(r"\b([A-Z]+-\d+)\b")
PLACEHOLDER_RE = re.compile(r"\b(TBD|TODO|FIXME)\b|\[[^\]]+\](?!\()", re.IGNORECASE)

COMMON_SPEC_SECTIONS = [
    "## Acceptance Criteria",
    "## Evidence Plan",
    "## Validation Plan",
    "## Non-goals",
    "## Provenance",
    "## Next Steps",
]

FEATURE_SPEC_SECTIONS = [
    "## Feature Description",
    "## Use Case",
    *COMMON_SPEC_SECTIONS,
]

OPEN_DATA_SPEC_SECTIONS = [
    "## Data Source",
    "## Use Case",
    "## Sample Payload",
    *COMMON_SPEC_SECTIONS,
]


class VerificationError(RuntimeError):
    """Raised when an external verification call fails."""


def parse_intake_markers(body: str) -> dict[str, str]:
    match = re.search(r"^\s*<!--\s*\n(?P<markers>.*?)\n-->", body, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError("GH issue body is missing the intake marker HTML comment block")

    markers: dict[str, str] = {}
    for line in match.group("markers").splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key:
            markers[key] = value
    return markers


def extract_linear_identifier(issue_body: str, comments: list[str]) -> str:
    combined = "\n".join([issue_body, *comments])
    url_match = LINEAR_URL_RE.search(combined)
    if url_match:
        return url_match.group(1).upper()

    for line in combined.splitlines():
        if "linear" not in line.lower():
            continue
        identifier_match = LINEAR_IDENTIFIER_RE.search(line)
        if identifier_match:
            return identifier_match.group(1).upper()

    return ""


def spec_path_for_session(root: Path, session_id: str) -> Path:
    return root / ".factory" / "intake" / session_id / "SPEC.md"


def section_body(text: str, heading: str) -> str:
    pattern = re.compile(
        rf"^{re.escape(heading)}\s*$\n(?P<body>.*?)(?=^#{{1,6}}\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    return match.group("body").strip() if match else ""


def validate_feature_spec_text(text: str, mode: str) -> list[str]:
    errors: list[str] = []
    expected_heading = "# Open-data SPEC: " if mode == "open-data" else "# Feature SPEC: "
    if not text.startswith(expected_heading):
        errors.append(f"SPEC is missing heading: {expected_heading}<title>")

    required_sections = OPEN_DATA_SPEC_SECTIONS if mode == "open-data" else FEATURE_SPEC_SECTIONS
    for section in required_sections:
        if section not in text:
            errors.append(f"SPEC is missing required section: {section}")

    criteria = re.findall(r"^- Given .+", section_body(text, "## Acceptance Criteria"), re.MULTILINE)
    if len(criteria) < 2:
        errors.append("SPEC is missing at least two acceptance criteria starting with '- Given'")

    if PLACEHOLDER_RE.search(text):
        errors.append("SPEC contains placeholder text; replace TBD/TODO/FIXME/bracket placeholders")

    return errors


def validate_linear_state(
    *,
    body: str,
    markers: dict[str, str],
    mode: str,
    labels: list[str],
    estimate: float | int | None,
    priority: int | None,
) -> list[str]:
    errors: list[str] = []
    for key, value in markers.items():
        if value and f"{key}: {value}" not in body:
            errors.append(f"Linear body is missing marker: {key}")

    for section in ["## Acceptance Criteria", "## Evidence Plan", "## Validation Plan"]:
        if section not in body:
            errors.append(f"Linear body is missing enriched section: {section}")

    if mode == "bug" and "## Root Cause Analysis" not in body and "## RCA" not in body:
        errors.append("Linear body is missing bug Root Cause Analysis section")
    if mode == "feature" and "## Feature Description" not in body:
        errors.append("Linear body is missing feature description section")
    if mode == "open-data" and "## Data Source" not in body:
        errors.append("Linear body is missing open-data source section")

    if "intake/needs-enrichment" in labels:
        errors.append("Linear issue still has intake/needs-enrichment label")
    if "intake/ready" not in labels:
        errors.append("Linear issue is missing intake/ready label")
    if estimate is None:
        errors.append("Linear issue estimate is not set")
    if priority is None or priority <= 0:
        errors.append("Linear issue priority is not set")

    return errors


def run_json(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(command, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise VerificationError(f"{' '.join(command)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def fetch_github_issue(repo: str, issue_number: int) -> dict[str, Any]:
    return run_json(
        [
            "gh",
            "issue",
            "view",
            str(issue_number),
            "--repo",
            repo,
            "--json",
            "body,comments,labels,url",
        ]
    )


class LinearClient:
    def __init__(self, api_key: str) -> None:
        self.api_key = api_key

    @classmethod
    def from_env(cls) -> "LinearClient":
        api_key = os.environ.get("LINEAR_API_KEY", "").strip()
        if not api_key:
            raise VerificationError("LINEAR_API_KEY is required to verify enrichment")
        return cls(api_key)

    def graphql(self, query: str, variables: dict[str, Any]) -> dict[str, Any]:
        payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
        request = urllib.request.Request(
            LINEAR_GRAPHQL_URL,
            data=payload,
            headers={
                "Authorization": self.api_key,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                data = json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError as error:
            raise VerificationError(f"Linear GraphQL request failed: {error}") from error
        if data.get("errors"):
            raise VerificationError(f"Linear GraphQL returned errors: {data['errors']}")
        return data["data"]

    def fetch_issue(self, identifier: str) -> dict[str, Any]:
        query = """
        query IssueByIdentifier($identifier: String!) {
          issues(filter: { identifier: { eq: $identifier } }, first: 1) {
            nodes {
              id
              identifier
              title
              url
              description
              estimate
              priority
              labels { nodes { name } }
            }
          }
        }
        """
        data = self.graphql(query, {"identifier": identifier})
        nodes = data["issues"]["nodes"]
        if not nodes:
            raise VerificationError(f"Linear issue not found: {identifier}")
        return nodes[0]


def validate_spec_file(root: Path, spec_path: Path, mode: str) -> list[str]:
    if not spec_path.exists():
        return [f"SPEC not found: {spec_path}"]

    if mode == "bug":
        result = subprocess.run(
            [sys.executable, str(root / "scripts" / "intake" / "bugfix_spec.py"), "validate", str(spec_path)],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            return [line for line in result.stderr.splitlines() if line] or ["bugfix SPEC validation failed"]
        return []

    return validate_feature_spec_text(spec_path.read_text(encoding="utf-8"), mode=mode)


def write_output(name: str, value: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"{name}={value}\n")
    else:
        print(f"{name}={value}")


def verify(args: argparse.Namespace) -> int:
    issue = fetch_github_issue(args.repo, args.gh_issue)
    issue_body = issue.get("body") or ""
    markers = parse_intake_markers(issue_body)
    mode = markers.get("Mode", "")
    if mode == "fact-check":
        print("fact-check intake does not require Stage-2 enrichment")
        return 0
    if mode not in {"bug", "feature", "open-data"}:
        print(f"unsupported intake mode: {mode}", file=sys.stderr)
        return 1

    comments = [comment.get("body", "") for comment in issue.get("comments", [])]
    linear_identifier = args.linear_identifier or extract_linear_identifier(issue_body, comments)
    if not linear_identifier:
        print("could not find linked Linear issue identifier in GH issue body or comments", file=sys.stderr)
        return 1

    linear_issue = LinearClient.from_env().fetch_issue(linear_identifier)
    labels = [label["name"] for label in linear_issue["labels"]["nodes"]]
    errors = validate_linear_state(
        body=linear_issue.get("description") or "",
        markers=markers,
        mode=mode,
        labels=labels,
        estimate=linear_issue.get("estimate"),
        priority=linear_issue.get("priority"),
    )

    session_id = markers.get("Intake-Session", "")
    spec_path = spec_path_for_session(args.root, session_id)
    errors.extend(validate_spec_file(args.root, spec_path, mode))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    relative_spec_path = spec_path.relative_to(args.root).as_posix()
    write_output("linear_url", linear_issue["url"])
    write_output("linear_identifier", linear_issue["identifier"])
    write_output("spec_path", relative_spec_path)
    print(f"verified enrichment for GH issue #{args.gh_issue}: {linear_issue['url']} {relative_spec_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Verify Stage-2 intake enrichment post-state.")
    parser.add_argument("--gh-issue", type=int, required=True)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "RiddimSoftware/epac"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--linear-identifier")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return verify(args)
    except (ValueError, VerificationError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
