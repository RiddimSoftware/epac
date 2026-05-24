#!/usr/bin/env python3
"""Post an evidence-regression summary as a comment on a Linear issue.

Used by .github/workflows/evidence-regression.yml when the workflow input
`linear_issue_id` is provided. Reads the report.md produced by
`evidence capture-pr`, plus the workflow run URL and PR number, and posts
a structured comment on the target Linear issue. The Linear API key is
fetched from AWS Secrets Manager (`linear/api-key`, us-east-1) following
the pattern in scripts/factory/set_linear_fields.py.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.request import Request, urlopen


LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
LINEAR_SECRET_ID = "linear/api-key"
SUMMARY_CHAR_LIMIT = 40_000  # well below Linear's 65k comment cap


def linear_api_key() -> str:
    env_key = os.environ.get("LINEAR_API_KEY", "").strip()
    if env_key:
        return env_key

    result = subprocess.run(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            LINEAR_SECRET_ID,
            "--region",
            "us-east-1",
            "--query",
            "SecretString",
            "--output",
            "text",
        ],
        capture_output=True,
        check=True,
        text=True,
    )
    secret = result.stdout.strip()
    try:
        decoded = json.loads(secret)
    except json.JSONDecodeError:
        return secret
    return (
        decoded.get("LINEAR_API_KEY")
        or decoded.get("api_key")
        or decoded.get("token")
        or secret
    )


def graphql(query: str, variables: dict[str, object], api_key: str) -> dict[str, object]:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    request = Request(
        LINEAR_GRAPHQL_URL,
        data=payload,
        headers={
            "Authorization": api_key,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(request) as response:
        body = response.read().decode("utf-8")
    parsed = json.loads(body)
    if "errors" in parsed:
        raise RuntimeError(f"Linear GraphQL error: {parsed['errors']}")
    return parsed["data"]


def resolve_issue_uuid(identifier_or_uuid: str, api_key: str) -> str:
    """Linear accepts either a UUID or a human identifier (e.g. EPAC-1985) for issue queries."""
    query = """
    query ResolveIssue($id: String!) {
      issue(id: $id) {
        id
        identifier
      }
    }
    """
    data = graphql(query, {"id": identifier_or_uuid}, api_key)
    issue = data.get("issue")
    if not issue:
        raise SystemExit(f"Linear issue not found: {identifier_or_uuid}")
    return issue["id"]


def post_comment(issue_uuid: str, body: str, api_key: str) -> str:
    mutation = """
    mutation CreateComment($input: CommentCreateInput!) {
      commentCreate(input: $input) {
        success
        comment {
          id
          url
        }
      }
    }
    """
    data = graphql(mutation, {"input": {"issueId": issue_uuid, "body": body}}, api_key)
    payload = data.get("commentCreate") or {}
    if not payload.get("success"):
        raise SystemExit(f"Linear commentCreate did not succeed: {payload!r}")
    return (payload.get("comment") or {}).get("url", "")


def build_comment_body(
    *,
    report_path: Path | None,
    run_url: str,
    pr_number: str,
    output_dir: str,
) -> str:
    parts: list[str] = []
    parts.append("## Evidence regression run")
    parts.append("")
    parts.append(f"- **Workflow run:** {run_url}")
    if pr_number:
        parts.append(f"- **PR:** #{pr_number}")
    parts.append(f"- **Output bundle:** `{output_dir}` (also attached as a workflow artifact)")
    parts.append("")

    if report_path and report_path.is_file():
        report = report_path.read_text(encoding="utf-8").strip()
        if len(report) > SUMMARY_CHAR_LIMIT:
            report = report[:SUMMARY_CHAR_LIMIT] + "\n\n_…truncated; see the workflow artifact for the full report._"
        parts.append("### Report")
        parts.append("")
        parts.append(report)
    else:
        parts.append("_No `report.md` was produced — check the workflow logs for failure details._")

    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linear-issue", required=True, help="Linear identifier (EPAC-1985) or UUID")
    parser.add_argument("--report", required=True, help="Path to evidence report.md")
    parser.add_argument("--run-url", required=True, help="GitHub Actions workflow run URL")
    parser.add_argument("--pr-number", default="", help="PR number, if applicable")
    parser.add_argument("--output-dir", required=True, help="Evidence output directory path")
    args = parser.parse_args()

    api_key = linear_api_key()
    if not api_key:
        print("LINEAR_API_KEY not available (env or Secrets Manager)", file=sys.stderr)
        return 1

    issue_uuid = resolve_issue_uuid(args.linear_issue, api_key)

    body = build_comment_body(
        report_path=Path(args.report),
        run_url=args.run_url,
        pr_number=args.pr_number,
        output_dir=args.output_dir,
    )

    comment_url = post_comment(issue_uuid, body, api_key)
    print(f"Posted Linear comment: {comment_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
