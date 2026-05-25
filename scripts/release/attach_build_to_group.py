#!/usr/bin/env python3
"""Attach a TestFlight build to a beta group in App Store Connect."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"
SECRET_ID = "appstore/connect-api"


class AttachBuildError(Exception):
    """Represents an unrecoverable ASC API error."""


class RetriesExhausted(AttachBuildError):
    """Raised after retry budget is exhausted."""


def get_asc_secret() -> dict[str, str]:
    """Fetch ASC API credentials from AWS Secrets Manager."""
    result = subprocess.run(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            SECRET_ID,
            "--region",
            "us-east-1",
            "--query",
            "SecretString",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def get_asc_credentials() -> tuple[str, str, str]:
    """Read ASC credentials from environment first, otherwise from Secrets Manager."""
    key_id = os.getenv("ASC_KEY_ID")
    issuer_id = os.getenv("ASC_ISSUER_ID")
    private_key = os.getenv("ASC_PRIVATE_KEY")

    if key_id and issuer_id and private_key:
        return key_id, issuer_id, private_key

    key_path = os.getenv("ASC_KEY_PATH")
    if key_id and issuer_id and key_path:
        return key_id, issuer_id, Path(os.path.expanduser(key_path)).read_text(encoding="utf-8")

    secret = get_asc_secret()
    private_key = secret.get("private_key") or secret.get("key")
    return secret["key_id"], secret["issuer_id"], private_key


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


def make_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def request_with_retries(
    method: str,
    path: str,
    token: str,
    max_retries: int = 3,
    base_delay: float = 1.0,
    **kwargs,
) -> requests.Response:
    """Call ASC with retries on 5xx responses only."""
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    if method != "GET":
        headers.setdefault("Content-Type", "application/json")

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.request(
                method,
                f"{BASE_URL}{path}",
                headers=headers,
                timeout=30,
                **kwargs,
            )
        except requests.RequestException as exc:
            if attempt == max_retries:
                raise AttachBuildError(f"{method} {path} failed: network error") from exc
            time.sleep(base_delay * (2 ** (attempt - 1)))
            continue

        if 500 <= response.status_code < 600 and attempt < max_retries:
            time.sleep(base_delay * (2 ** (attempt - 1)))
            continue

        return response

    raise RetriesExhausted(f"{method} {path} failed after {max_retries} attempts")


def find_group_id(
    group_name: str,
    token: str,
    bundle_id: str | None = None,
) -> str:
    """Resolve a beta group ID by name (optionally scoped by bundle ID)."""
    params: dict[str, str] = {
        "filter[name]": group_name,
        "limit": "200",
    }
    if bundle_id:
        params["filter[app]"] = bundle_id

    response = request_with_retries("GET", "/betaGroups", token, params=params)

    if response.status_code in (200, 404):
        data = response.json().get("data", [])
        if data:
            return data[0]["id"]

        if bundle_id:
            raise AttachBuildError(f"beta group not found: name={group_name}, bundle_id={bundle_id}")
        raise AttachBuildError(f"beta group not found: name={group_name}")

    raise AttachBuildError(f"beta group lookup failed ({response.status_code}): {response.text}")


def attach_build(group_id: str, build_id: str, token: str) -> dict[str, str | bool]:
    """Attach build to group. Returns output payload for success-path logging."""
    payload = {
        "data": [
            {
                "type": "builds",
                "id": build_id,
            }
        ]
    }
    response = request_with_retries(
        "POST",
        f"/betaGroups/{group_id}/relationships/builds",
        token,
        json=payload,
    )

    if response.status_code == 201:
        return {"attached": True, "build_id": build_id, "group_id": group_id}

    if response.status_code == 409:
        return {"attached": False, "reason": "already_attached"}

    if response.status_code == 404:
        # Keep response payload to aid diagnostics.
        raise AttachBuildError(f"attach build failed: not found ({response.status_code}): {response.text}")

    raise AttachBuildError(f"attach build failed ({response.status_code}): {response.text}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--group-name", required=True)
    parser.add_argument("--bundle-id", default="")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    bundle_id = args.bundle_id.strip() or None

    key_id, issuer_id, private_key = get_asc_credentials()
    token = get_asc_token(key_id, issuer_id, private_key)

    try:
        group_id = find_group_id(args.group_name, token, bundle_id=bundle_id)
        result = attach_build(group_id, args.build_id, token)
    except AttachBuildError as exc:
        message = str(exc)
        if message.startswith("beta group not found:"):
            print(json.dumps({"error": "group_not_found", "message": message, "group_name": args.group_name, "bundle_id": bundle_id}), flush=True)
            return 3

        print(json.dumps({"error": "request_failed", "message": message}), flush=True)
        return 1

    print(json.dumps(result), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
