#!/usr/bin/env python3
"""
Poll App Store Connect build processing status until it is accepted.

Usage:
  wait_for_build_processed.py --build-id <id> [--timeout-minutes 240] [--poll-interval-seconds 60]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any

import jwt
import requests


ASC_BASE_URL = "https://api.appstoreconnect.apple.com/v1/builds/{build_id}"
DEFAULT_TIMEOUT_SECONDS = 240 * 60
DEFAULT_POLL_INTERVAL_SECONDS = 60


def get_asc_secret() -> dict[str, str]:
    """Fetch App Store Connect credentials from AWS Secrets Manager."""
    aws_profile = os.environ.get("AWS_PROFILE", "riddim-agent")
    env = os.environ.copy()
    env["AWS_PROFILE"] = aws_profile

    result = subprocess.run(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            "appstore/connect-api",
            "--region",
            "us-east-1",
            "--query",
            "SecretString",
            "--output",
            "text",
        ],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    secret = json.loads(result.stdout)
    secret_key = secret.get("key") or secret.get("private_key")
    if not secret_key:
        raise RuntimeError("secret missing private key material")
    return {
        "key_id": secret["key_id"],
        "issuer_id": secret["issuer_id"],
        "private_key": secret_key,
    }


def get_asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    """Create an App Store Connect API JWT."""
    now = int(__import__("time").time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def get_build(
    build_id: str,
    token: str,
) -> dict[str, Any]:
    headers = {"Authorization": f"Bearer {token}"}
    url = ASC_BASE_URL.format(build_id=build_id)
    response = requests.get(url, headers=headers, timeout=30)
    response.raise_for_status()
    return response.json()


def extract_rejection_reason(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Return structured rejection information from an ASC error response."""
    raw_errors = payload.get("errors")
    if not isinstance(raw_errors, list):
        return [{"error": "No errors array in ASC response"}]

    reasons = []
    for error in raw_errors:
        if not isinstance(error, dict):
            reasons.append({"detail": str(error)})
            continue
        reasons.append(
            {
                "code": error.get("code"),
                "id": error.get("id"),
                "status": error.get("status"),
                "title": error.get("title"),
                "detail": error.get("detail"),
            }
        )
    return reasons


def wait_for_build_processed(
    build_id: str,
    token: str,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    poll_interval_seconds: int = DEFAULT_POLL_INTERVAL_SECONDS,
    current_time: callable = None,
    sleep: callable = None,
    get_build_fn: callable = None,
) -> tuple[int, dict[str, Any]]:
    if current_time is None:
        from time import time as current_time  # local import to allow test substitution
    if sleep is None:
        from time import sleep  # local import to allow test substitution
    if get_build_fn is None:
        get_build_fn = get_build

    start = current_time()
    last_state = "UNKNOWN"
    while True:
        payload = get_build_fn(build_id, token)
        data = payload.get("data", {})
        attrs = data.get("attributes", {}) if isinstance(data, dict) else {}
        state = str(attrs.get("processingState") or "UNKNOWN").upper()
        expired = bool(attrs.get("expired", False))
        last_state = state

        if expired:
            elapsed = current_time() - start
            return 7, {
                "build_id": build_id,
                "expired": True,
                "processing_state": state,
                "wait_seconds": int(elapsed),
                "expiration_date": attrs.get("expirationDate"),
            }

        if state == "VALID":
            elapsed = current_time() - start
            return 0, {
                "build_id": build_id,
                "processing_state": state,
                "wait_seconds": int(elapsed),
            }

        if state == "INVALID":
            elapsed = current_time() - start
            return 6, {
                "build_id": build_id,
                "processing_state": state,
                "wait_seconds": int(elapsed),
                "rejection": extract_rejection_reason(payload),
            }

        elapsed = current_time() - start
        if elapsed >= timeout_seconds:
            return 5, {
                "build_id": build_id,
                "timed_out": True,
                "last_state": last_state,
                "elapsed_seconds": int(elapsed),
            }

        sleep(max(0, poll_interval_seconds))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-id", required=True, help="ASC build ID")
    parser.add_argument(
        "--timeout-minutes",
        type=float,
        default=240,
        help="Maximum wait time in minutes (default: 240)",
    )
    parser.add_argument(
        "--poll-interval-seconds",
        type=float,
        default=60,
        help="Polling period in seconds (default: 60)",
    )

    args = parser.parse_args()

    timeout_seconds = int(args.timeout_minutes * 60)
    poll_interval_seconds = int(args.poll_interval_seconds)
    if timeout_seconds <= 0:
        print(json.dumps({"error": "timeout-minutes must be > 0"}))
        sys.exit(1)
    if poll_interval_seconds <= 0:
        print(json.dumps({"error": "poll-interval-seconds must be > 0"}))
        sys.exit(1)

    try:
        secret = get_asc_secret()
        token = get_asc_token(secret["key_id"], secret["issuer_id"], secret["private_key"])
        status, payload = wait_for_build_processed(
            args.build_id,
            token,
            timeout_seconds=timeout_seconds,
            poll_interval_seconds=poll_interval_seconds,
        )
    except Exception as exc:  # pragma: no cover - defensive CLI path
        print(
            json.dumps({
                "build_id": args.build_id,
                "error": str(exc),
            })
        )
        sys.exit(1)

    print(json.dumps(payload))
    sys.exit(status)


if __name__ == "__main__":
    main()
