#!/usr/bin/env python3
"""
Verify ASC API key has write scope for betaTesters and betaAppReviewSubmissions.

Fetches the ASC key from AWS Secrets Manager and tests two endpoints:
  1. POST /v1/betaTesters — create a test tester, delete immediately if successful
  2. POST /v1/betaAppReviewSubmissions — submit most recent valid build for review

Outputs a JSON report to stdout with endpoint status and any errors.

Usage:
  AWS_PROFILE=riddim-agent python3 scripts/release/verify_asc_write_scope.py
"""
import json
import os
import sys
import time
import uuid
from datetime import datetime

import jwt
import requests


def get_asc_secret() -> dict:
    """Fetch ASC API credentials from AWS Secrets Manager."""
    import subprocess

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
    """Generate a signed JWT for ASC API authentication."""
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def get_beta_groups(app_id: str, token: str) -> tuple[int, dict, list[str]]:
    """List existing beta groups (read-scope sanity check). Returns status, response, and group IDs."""
    headers = {"Authorization": f"Bearer {token}"}
    url = "https://api.appstoreconnect.apple.com/v1/betaGroups"
    params = {"filter[app]": app_id}

    try:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        data = resp.json() if resp.text else {}
        group_ids = [g["id"] for g in data.get("data", [])]
        return resp.status_code, data, group_ids
    except requests.RequestException as e:
        return 0, {"error": str(e)}, []


def get_latest_valid_build(app_id: str, token: str) -> tuple[str | None, dict]:
    """Fetch the most recent VALID build for the app."""
    headers = {"Authorization": f"Bearer {token}"}
    url = "https://api.appstoreconnect.apple.com/v1/builds"
    params = {
        "filter[app]": app_id,
        "filter[processingState]": "VALID",
        "sort": "-uploadedDate",
        "limit": 1,
    }

    try:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if data.get("data"):
            return data["data"][0]["id"], {}
        return None, {"message": "No VALID builds found"}
    except requests.RequestException as e:
        return None, {"error": str(e)}


def test_beta_tester_endpoint(
    app_id: str, token: str, beta_group_id: str | None, build_id: str | None
) -> tuple[str, int, dict]:
    """
    Test POST /v1/betaTesters by creating and deleting a test tester.

    Returns: (status_desc, http_status, response_data)
    """
    headers = {"Authorization": f"Bearer {token}"}
    url = "https://api.appstoreconnect.apple.com/v1/betaTesters"

    # Create test tester with unique email
    test_uuid = uuid.uuid4().hex[:8]
    test_date = datetime.now().strftime("%Y%m%d")
    test_email = f"asc-write-scope-test+{test_uuid}@riddimsoftware.com"

    payload = {
        "data": {
            "type": "betaTesters",
            "attributes": {
                "email": test_email,
                "firstName": "ScopeTest",
                "lastName": test_date,
            },
        }
    }

    # Add relationship (prefer builds over betaGroups if available)
    if build_id:
        payload["data"]["relationships"] = {
            "builds": {
                "data": [{"type": "builds", "id": build_id}]
            }
        }
    elif beta_group_id:
        payload["data"]["relationships"] = {
            "betaGroups": {
                "data": [{"type": "betaGroups", "id": beta_group_id}]
            }
        }

    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=30)

        if resp.status_code == 201:
            # Successfully created; now delete it
            tester_id = resp.json()["data"]["id"]
            delete_url = f"{url}/{tester_id}"

            try:
                del_resp = requests.delete(delete_url, headers=headers, timeout=30)
                if 200 <= del_resp.status_code < 300:
                    return "ok", resp.status_code, {"message": "Created and deleted test tester"}
                else:
                    return "other", resp.status_code, {
                        "message": f"Created tester but deletion failed: {del_resp.status_code}",
                        "tester_id": tester_id,
                    }
            except requests.RequestException as e:
                return "other", resp.status_code, {
                    "message": f"Created tester but deletion error: {str(e)}",
                    "tester_id": tester_id,
                }
        elif resp.status_code == 403:
            return "denied", resp.status_code, resp.json() if resp.text else {}
        else:
            return "other", resp.status_code, resp.json() if resp.text else {}

    except requests.RequestException as e:
        return "other", 0, {"error": str(e)}


def test_beta_app_review_endpoint(app_id: str, build_id: str, token: str) -> tuple[str, int, dict]:
    """
    Test POST /v1/betaAppReviewSubmissions by attempting to submit a build.

    Returns: (status_desc, http_status, response_data)
    """
    headers = {"Authorization": f"Bearer {token}"}
    url = "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions"

    payload = {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {
                    "data": {"type": "builds", "id": build_id}
                }
            },
        }
    }

    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=30)

        if resp.status_code in (200, 201):
            return "ok", resp.status_code, resp.json() if resp.text else {}
        elif resp.status_code == 409:
            # Build already submitted or other conflict — endpoint is reachable
            return "ok", resp.status_code, resp.json() if resp.text else {}
        elif resp.status_code == 422:
            # Unprocessable entity — endpoint is reachable and accepting writes,
            # but the build metadata is incomplete. This indicates write scope.
            return "ok", resp.status_code, resp.json() if resp.text else {}
        elif resp.status_code == 403:
            return "denied", resp.status_code, resp.json() if resp.text else {}
        else:
            return "other", resp.status_code, resp.json() if resp.text else {}

    except requests.RequestException as e:
        return "other", 0, {"error": str(e)}


def main() -> None:
    app_id = "1224459142"  # epac App Store Connect app ID

    try:
        secret = get_asc_secret()
        key_id = secret["key_id"]
        issuer_id = secret["issuer_id"]
        private_key = secret["private_key"]
    except Exception as e:
        print(
            json.dumps({
                "betaTesters": f"other:fetch-secret",
                "betaAppReviewSubmissions": f"other:fetch-secret",
                "error": str(e),
            })
        )
        sys.exit(1)

    token = get_asc_token(key_id, issuer_id, private_key)

    # Sanity check: list existing beta groups (read scope)
    status_code, response, beta_group_ids = get_beta_groups(app_id, token)
    if status_code != 200:
        print(
            json.dumps({
                "betaTesters": "other:sanity-check",
                "betaAppReviewSubmissions": "other:sanity-check",
                "error": f"Beta groups list returned {status_code}",
                "response": response,
            })
        )
        sys.exit(1)

    # Get the latest valid build for both tests
    build_id, build_fetch_response = get_latest_valid_build(app_id, token)

    # Test betaTesters endpoint
    beta_group_id = beta_group_ids[0] if beta_group_ids else None
    beta_testers_status, beta_testers_code, beta_testers_response = test_beta_tester_endpoint(
        app_id, token, beta_group_id, build_id
    )

    if build_id:
        beta_app_review_status, beta_app_review_code, beta_app_review_response = (
            test_beta_app_review_endpoint(app_id, build_id, token)
        )
    else:
        beta_app_review_status = "other"
        beta_app_review_code = 0
        beta_app_review_response = {"message": "No VALID builds found", **build_fetch_response}

    # Output JSON report
    report = {
        "betaTesters": beta_testers_status,
        "betaAppReviewSubmissions": beta_app_review_status,
    }

    # Include response details for debugging
    if beta_testers_status != "ok":
        report["betaTesters_status_code"] = beta_testers_code
        if beta_testers_response:
            report["betaTesters_response"] = beta_testers_response

    if beta_app_review_status != "ok":
        report["betaAppReviewSubmissions_status_code"] = beta_app_review_code
        if beta_app_review_response:
            report["betaAppReviewSubmissions_response"] = beta_app_review_response

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
