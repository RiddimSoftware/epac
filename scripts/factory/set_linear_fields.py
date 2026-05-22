#!/usr/bin/env python3
"""Update Linear estimate and priority fields for an intake mirror issue."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from urllib.request import Request, urlopen


LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
LINEAR_ESTIMATES = {1, 2, 4, 8, 16, 24, 40}
LINEAR_PRIORITIES = {0, 1, 2, 3, 4}
LINEAR_SECRET_ID = "linear/api-key"


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


def validate_linear_fields(estimate: int, priority: int) -> None:
    if estimate not in LINEAR_ESTIMATES:
        raise ValueError(f"estimate must be one of {sorted(LINEAR_ESTIMATES)}")
    if priority not in LINEAR_PRIORITIES:
        raise ValueError(f"priority must be one of {sorted(LINEAR_PRIORITIES)}")


def build_issue_update_payload(issue_id: str, estimate: int, priority: int) -> dict[str, object]:
    validate_linear_fields(estimate, priority)
    mutation = """
    mutation UpdateIssueFields($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue {
          id
          estimate
          priority
        }
      }
    }
    """
    return {
        "query": mutation,
        "variables": {
            "id": issue_id,
            "input": {
                "estimate": estimate,
                "priority": priority,
            },
        },
    }


def set_linear_fields(issue_id: str, estimate: int, priority: int, api_key: str) -> None:
    payload = build_issue_update_payload(issue_id, estimate, priority)
    req = Request(
        LINEAR_GRAPHQL_URL,
        data=json.dumps(payload).encode(),
        headers={"Authorization": api_key, "Content-Type": "application/json"},
    )
    with urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
    if data.get("errors"):
        raise RuntimeError(f"Linear issueUpdate failed: {data['errors']}")
    update = data.get("data", {}).get("issueUpdate", {})
    if not update.get("success"):
        raise RuntimeError(f"Linear issueUpdate did not succeed: {data}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--linear-issue", required=True)
    parser.add_argument("--estimate", required=True, type=int)
    parser.add_argument("--priority", required=True, type=int)
    args = parser.parse_args(argv)

    set_linear_fields(args.linear_issue, args.estimate, args.priority, linear_api_key())
    print(
        f"Updated Linear issue {args.linear_issue} "
        f"with estimate {args.estimate} and priority {args.priority}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
