#!/usr/bin/env python3
"""Find the Linear mirror issue linked to a GitHub issue attachment."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from typing import Callable
from urllib.request import Request, urlopen


LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
DEFAULT_TIMEOUT_SECONDS = 60
DEFAULT_INTERVAL_SECONDS = 5
LINEAR_SECRET_ID = "linear/api-key"


def github_issue_url(repo: str, issue_number: int) -> str:
    return f"https://github.com/{repo}/issues/{issue_number}"


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
    return decoded.get("LINEAR_API_KEY") or decoded.get("api_key") or decoded.get("token") or secret


def query_issue_id_for_attachment(url: str, api_key: str) -> str | None:
    query = """
    query IssueByAttachmentUrl($url: String!) {
      attachments(filter: { url: { eq: $url } }, first: 10) {
        nodes {
          issue {
            id
            identifier
          }
        }
      }
    }
    """
    body = json.dumps({"query": query, "variables": {"url": url}}).encode()
    req = Request(
        LINEAR_GRAPHQL_URL,
        data=body,
        headers={"Authorization": api_key, "Content-Type": "application/json"},
    )
    with urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
    if data.get("errors"):
        raise RuntimeError(f"Linear attachment lookup failed: {data['errors']}")
    nodes = data.get("data", {}).get("attachments", {}).get("nodes", [])
    for node in nodes:
        issue = node.get("issue")
        if issue and issue.get("id"):
            return issue["id"]
    return None


def wait_for_linear_issue(
    repo: str,
    issue_number: int,
    api_key: str,
    *,
    query_issue_id: Callable[[str, str], str | None] = query_issue_id_for_attachment,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    interval_seconds: int = DEFAULT_INTERVAL_SECONDS,
) -> str:
    url = github_issue_url(repo, issue_number)
    deadline = time.monotonic() + timeout_seconds
    while True:
        issue_id = query_issue_id(url, api_key)
        if issue_id:
            return issue_id
        if time.monotonic() >= deadline:
            raise TimeoutError(
                f"Timed out waiting {timeout_seconds}s for Linear attachment for {url}"
            )
        time.sleep(interval_seconds)


def _write_github_output(issue_id: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as output:
        output.write(f"issue_id={issue_id}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gh-repo", required=True)
    parser.add_argument("--gh-issue", required=True, type=int)
    parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--interval-seconds", type=int, default=DEFAULT_INTERVAL_SECONDS)
    args = parser.parse_args(argv)

    issue_id = wait_for_linear_issue(
        args.gh_repo,
        args.gh_issue,
        linear_api_key(),
        timeout_seconds=args.timeout_seconds,
        interval_seconds=args.interval_seconds,
    )
    _write_github_output(issue_id)
    print(f"Resolved Linear issue id: {issue_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
