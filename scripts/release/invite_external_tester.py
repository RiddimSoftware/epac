#!/usr/bin/env python3
"""
Idempotent CLI for inviting an external tester to a TestFlight beta group.

Adds a tester to a named beta group via App Store Connect API. If the tester
already exists, patches the group relationship if needed. Optionally posts a
GitHub issue comment on success.

Usage:
  AWS_PROFILE=riddim-agent python3 scripts/release/invite_external_tester.py \
    --email reporter@example.com \
    --group-name PublicTesting \
    [--first-name Jane] \
    [--last-name Doe] \
    [--gh-issue 123] \
    [--gh-repo RiddimSoftware/epac]
"""
import argparse
import json
import re
import subprocess
import sys
import time

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "1224459142"


def validate_email(email: str) -> bool:
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email))


def first_name_from_email(email: str) -> str:
    local = email.split("@")[0]
    parts = re.split(r"[._\-+]", local)
    return parts[0].capitalize() if parts and parts[0] else "Tester"


def get_asc_secret() -> dict:
    result = subprocess.run(
        [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "appstore/connect-api",
            "--region", "us-east-1",
            "--query", "SecretString",
            "--output", "text",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def get_asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def asc_get(path: str, token: str, params: dict | None = None) -> requests.Response:
    headers = {"Authorization": f"Bearer {token}"}
    return requests.get(f"{BASE_URL}{path}", headers=headers, params=params or {}, timeout=30)


def asc_post(path: str, token: str, payload: dict) -> requests.Response:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    return requests.post(f"{BASE_URL}{path}", headers=headers, json=payload, timeout=30)


def asc_patch(path: str, token: str, payload: dict) -> requests.Response:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    return requests.patch(f"{BASE_URL}{path}", headers=headers, json=payload, timeout=30)


def resolve_beta_group(group_name: str, token: str) -> str:
    resp = asc_get("/betaGroups", token, {"filter[name]": group_name, "filter[app]": APP_ID})
    if not resp.ok:
        raise SystemExit(json.dumps({
            "error": f"GET /betaGroups failed ({resp.status_code})",
            "detail": resp.text,
        }))
    groups = resp.json().get("data", [])
    matching = [g for g in groups if g.get("attributes", {}).get("name") == group_name]
    if not matching:
        raise SystemExit(json.dumps({"error": f"Beta group '{group_name}' not found"}))
    return matching[0]["id"]


def get_existing_tester(email: str, token: str) -> dict | None:
    resp = asc_get("/betaTesters", token, {"filter[email]": email})
    if not resp.ok:
        return None
    data = resp.json().get("data", [])
    return data[0] if data else None


def tester_in_group(tester_id: str, group_id: str, token: str) -> bool:
    resp = asc_get(f"/betaTesters/{tester_id}/betaGroups", token)
    if not resp.ok:
        return False
    group_ids = [g["id"] for g in resp.json().get("data", [])]
    return group_id in group_ids


def add_tester_to_group(tester_id: str, group_id: str, token: str) -> bool:
    payload = {"data": [{"type": "betaGroups", "id": group_id}]}
    resp = asc_patch(f"/betaTesters/{tester_id}/relationships/betaGroups", token, payload)
    return resp.ok


def post_gh_comment(gh_repo: str, gh_issue: int, email: str) -> None:
    body = (
        f"Invited {email} to PublicTesting; "
        "TestFlight invitation will arrive in their inbox shortly."
    )
    subprocess.run(
        ["gh", "issue", "comment", str(gh_issue), "--repo", gh_repo, "--body", body],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Invite external tester to TestFlight beta group")
    parser.add_argument("--email", required=True)
    parser.add_argument("--group-name", required=True)
    parser.add_argument("--first-name", default=None)
    parser.add_argument("--last-name", default="Tester")
    parser.add_argument("--gh-issue", type=int, default=None)
    parser.add_argument("--gh-repo", default="RiddimSoftware/epac")
    args = parser.parse_args()

    if not validate_email(args.email):
        print(json.dumps({"error": f"Invalid email address: {args.email}"}))
        sys.exit(2)

    first_name = args.first_name or first_name_from_email(args.email)
    last_name = args.last_name

    try:
        secret = get_asc_secret()
        token = get_asc_token(secret["key_id"], secret["issuer_id"], secret["private_key"])
    except Exception as e:
        print(json.dumps({"error": f"Failed to obtain ASC token: {e}"}))
        sys.exit(1)

    try:
        group_id = resolve_beta_group(args.group_name, token)
    except SystemExit as exc:
        print(str(exc))
        sys.exit(1)

    payload = {
        "data": {
            "type": "betaTesters",
            "attributes": {
                "email": args.email,
                "firstName": first_name,
                "lastName": last_name,
            },
            "relationships": {
                "betaGroups": {
                    "data": [{"type": "betaGroups", "id": group_id}]
                }
            },
        }
    }

    resp = asc_post("/betaTesters", token, payload)

    if resp.status_code == 201:
        tester_id = resp.json()["data"]["id"]
        print(json.dumps({"added": True, "tester_id": tester_id}))
        if args.gh_issue is not None:
            post_gh_comment(args.gh_repo, args.gh_issue, args.email)
        sys.exit(0)

    if resp.status_code == 409:
        tester = get_existing_tester(args.email, token)
        if tester is None:
            print(json.dumps({"error": "409 from POST /betaTesters but existing tester not found"}))
            sys.exit(1)

        tester_id = tester["id"]
        if tester_in_group(tester_id, group_id, token):
            print(json.dumps({"added": False, "tester_id": tester_id, "reason": "already_member"}))
            sys.exit(0)

        if add_tester_to_group(tester_id, group_id, token):
            print(json.dumps({"added": False, "tester_id": tester_id, "reason": "added_to_group"}))
            if args.gh_issue is not None:
                post_gh_comment(args.gh_repo, args.gh_issue, args.email)
            sys.exit(0)
        else:
            print(json.dumps({"error": "Failed to add existing tester to group"}))
            sys.exit(1)

    try:
        detail = resp.json()
    except Exception:
        detail = resp.text
    print(json.dumps({
        "error": f"POST /betaTesters failed ({resp.status_code})",
        "detail": detail,
    }))
    sys.exit(1)


if __name__ == "__main__":
    main()
