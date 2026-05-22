#!/usr/bin/env python3
"""Report a stuck Stage-2 intake enrichment run."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from typing import Any


LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"


def build_stuck_comment(*, gh_issue: int, run_url: str, reason: str) -> str:
    reason_text = "timed out" if reason == "timeout" else "failed"
    return (
        f"Enrichment stuck for GH issue #{gh_issue}: the Opus enrichment run {reason_text}.\n\n"
        f"Run: {run_url}\n\n"
        "Next action: operator should inspect the Opus run, decide whether to rerun enrichment, "
        "and update the Human Handoff checklist item when resolved."
    )


def append_checklist_item(body: str, item: str) -> str:
    if item in body:
        return body

    section_match = re.search(r"^## Discovered blockers\s*$", body, re.MULTILINE)
    if not section_match:
        suffix = "" if body.endswith("\n") else "\n"
        return f"{body}{suffix}\n## Discovered blockers\n{item}\n"

    next_section = re.search(r"^##\s+", body[section_match.end() :], re.MULTILINE)
    insert_at = section_match.end() + next_section.start() if next_section else len(body)
    prefix = body[:insert_at].rstrip()
    suffix = body[insert_at:].lstrip("\n")
    separator = "\n\n" if suffix else "\n"
    return f"{prefix}\n{item}{separator}{suffix}"


class LinearClient:
    def __init__(self, api_key: str) -> None:
        self.api_key = api_key

    @classmethod
    def from_env(cls) -> "LinearClient | None":
        api_key = os.environ.get("LINEAR_API_KEY", "").strip()
        return cls(api_key) if api_key else None

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
            raise RuntimeError(f"Linear GraphQL request failed: {error}") from error
        if data.get("errors"):
            raise RuntimeError(f"Linear GraphQL returned errors: {data['errors']}")
        return data["data"]

    def fetch_issue(self, identifier: str) -> dict[str, Any]:
        query = """
        query IssueByIdentifier($identifier: String!) {
          issues(filter: { identifier: { eq: $identifier } }, first: 1) {
            nodes { id identifier title url description }
          }
        }
        """
        data = self.graphql(query, {"identifier": identifier})
        nodes = data["issues"]["nodes"]
        if not nodes:
            raise RuntimeError(f"Linear issue not found: {identifier}")
        return nodes[0]

    def find_human_handoff_issue(self, team_key: str) -> dict[str, Any]:
        query = """
        query HumanHandoffIssue($teamKey: String!) {
          issues(filter: { team: { key: { eq: $teamKey } } }, first: 100) {
            nodes {
              id
              identifier
              title
              url
              description
              labels { nodes { name } }
            }
          }
        }
        """
        data = self.graphql(query, {"teamKey": team_key})
        nodes = [
            node
            for node in data["issues"]["nodes"]
            if any(label["name"] == "human-handoff" for label in node["labels"]["nodes"])
        ]
        for node in nodes:
            title = node["title"].lower()
            if "human handoff" in title or "handoff" in title:
                return node
        if nodes:
            return nodes[0]
        raise RuntimeError(f"No human-handoff Linear issue found for team {team_key}")

    def update_description(self, issue_id: str, description: str) -> None:
        mutation = """
        mutation UpdateIssueDescription($id: String!, $description: String!) {
          issueUpdate(id: $id, input: { description: $description }) {
            success
          }
        }
        """
        self.graphql(mutation, {"id": issue_id, "description": description})


def post_github_comment(repo: str, gh_issue: int, body: str) -> None:
    result = subprocess.run(
        ["gh", "issue", "comment", str(gh_issue), "--repo", repo, "--body", body],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(f"gh issue comment failed: {result.stderr.strip()}")


def handoff_item(args: argparse.Namespace) -> str:
    if getattr(args, "checklist_item", ""):
        return args.checklist_item
    return (
        f"- [ ] {args.issue_id}: Opus enrichment {args.reason} for GH issue #{args.gh_issue}; "
        f"operator should inspect the run: {args.run_url}"
    )


def update_human_handoff(args: argparse.Namespace, item: str) -> None:
    client = LinearClient.from_env()
    if client is None:
        print("LINEAR_API_KEY is not set; skipping Human Handoff checklist update", file=sys.stderr)
        return

    identifier = args.human_handoff_identifier or os.environ.get("HUMAN_HANDOFF_LINEAR_IDENTIFIER", "")
    if identifier:
        issue = client.fetch_issue(identifier)
    else:
        issue = client.find_human_handoff_issue(args.team_key)
    updated = append_checklist_item(issue.get("description") or "", item)
    if updated == (issue.get("description") or ""):
        print(f"Human Handoff already contains checklist item: {issue['url']}")
        return
    client.update_description(issue["id"], updated)
    print(f"Updated Human Handoff checklist: {issue['url']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Report a stuck intake enrichment run.")
    parser.add_argument("--gh-issue", type=int, required=True)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "RiddimSoftware/epac"))
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--reason", choices=["timeout", "failed"], required=True)
    parser.add_argument("--issue-id", default=os.environ.get("LINEAR_ISSUE_ID", "EPAC-1966"))
    parser.add_argument("--team-key", default=os.environ.get("LINEAR_TEAM_KEY", "EPAC"))
    parser.add_argument("--human-handoff-identifier")
    parser.add_argument("--checklist-item", default="")
    parser.add_argument("--skip-gh-comment", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    comment = build_stuck_comment(gh_issue=args.gh_issue, run_url=args.run_url, reason=args.reason)
    item = handoff_item(args)

    try:
        if not args.skip_gh_comment:
            post_github_comment(args.repo, args.gh_issue, comment)
        update_human_handoff(args, item)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
