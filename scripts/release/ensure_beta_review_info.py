#!/usr/bin/env python3
"""Ensure beta review prerequisites exist before submitting a build for review.

App Store Connect requires two resources before a beta review submission succeeds:
1. betaAppReviewDetail (app-level) — contact information for the review team
2. betaBuildLocalizations (build-level) — "What to Test" text per locale

This script checks for both and creates them if missing. It is idempotent.

Usage:
  ensure_beta_review_info.py --app-id <id> --build-id <id> [--whats-new <text>]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"
REVIEW_CONTACT_FIELDS = {
    "contactEmail": "BETA_REVIEW_CONTACT_EMAIL",
    "contactFirstName": "BETA_REVIEW_CONTACT_FIRST_NAME",
    "contactLastName": "BETA_REVIEW_CONTACT_LAST_NAME",
    "contactPhone": "BETA_REVIEW_CONTACT_PHONE",
}


def get_asc_credentials() -> tuple[str, str, str]:
    key_id = os.getenv("ASC_KEY_ID")
    issuer_id = os.getenv("ASC_ISSUER_ID")
    private_key = os.getenv("ASC_PRIVATE_KEY")

    if key_id and issuer_id and private_key:
        return key_id, issuer_id, private_key

    key_path = os.getenv("ASC_KEY_PATH")
    if key_id and issuer_id and key_path:
        return key_id, issuer_id, Path(os.path.expanduser(key_path)).read_text(encoding="utf-8")

    aws_profile = os.environ.get("AWS_PROFILE", "riddim-agent")
    env = os.environ.copy()
    env["AWS_PROFILE"] = aws_profile
    result = subprocess.run(
        [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "appstore/connect-api",
            "--region", "us-east-1",
            "--query", "SecretString",
            "--output", "text",
        ],
        check=True, capture_output=True, text=True, env=env,
    )
    secret = json.loads(result.stdout)
    secret_key = secret.get("key") or secret.get("private_key")
    if not secret_key:
        raise RuntimeError("secret missing private key material")
    return secret["key_id"], secret["issuer_id"], secret_key


def get_asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    import time
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def ensure_beta_app_review_detail(
    app_id: str,
    token: str,
    contact_email: str,
    contact_first_name: str,
    contact_last_name: str,
    contact_phone: str,
    *,
    http_get=None,
    http_patch=None,
) -> dict:
    if http_get is None:
        http_get = requests.get
    if http_patch is None:
        http_patch = requests.patch

    headers = {"Authorization": f"Bearer {token}"}
    url = f"{BASE_URL}/apps/{app_id}/betaAppReviewDetail"
    response = http_get(url, headers=headers, timeout=30)

    if response.status_code == 200:
        data = response.json().get("data", {})
        attrs = data.get("attributes", {}) if isinstance(data, dict) else {}
        missing_fields = [field for field in REVIEW_CONTACT_FIELDS if not attrs.get(field)]
        if not missing_fields:
            return {"status": "exists", "id": data.get("id", "")}

        detail_id = data.get("id", "")
        if detail_id:
            contact_values = {
                "contactEmail": contact_email,
                "contactFirstName": contact_first_name,
                "contactLastName": contact_last_name,
                "contactPhone": contact_phone,
            }
            missing_inputs = [
                field for field in missing_fields
                if not contact_values.get(field)
            ]
            if missing_inputs:
                return {
                    "status": "skipped",
                    "id": detail_id,
                    "missing_fields": [
                        f"{f} ({REVIEW_CONTACT_FIELDS[f]})" for f in missing_inputs
                    ],
                }
            patch_url = f"{BASE_URL}/betaAppReviewDetails/{detail_id}"
            patch_payload = {
                "data": {
                    "type": "betaAppReviewDetails",
                    "id": detail_id,
                    "attributes": {
                        field: contact_values[field]
                        for field in missing_fields
                    },
                }
            }
            patch_headers = {**headers, "Content-Type": "application/json"}
            patch_resp = http_patch(patch_url, headers=patch_headers, json=patch_payload, timeout=30)
            if patch_resp.status_code in (200, 204):
                return {"status": "updated", "id": detail_id}
            raise RuntimeError(
                f"Failed to update betaAppReviewDetail {detail_id}: "
                f"{patch_resp.status_code} {patch_resp.text}"
            )

    if response.status_code == 404:
        raise RuntimeError(
            f"betaAppReviewDetail not found for app {app_id}. "
            "Create it manually in App Store Connect first."
        )

    raise RuntimeError(
        f"Failed to fetch betaAppReviewDetail for app {app_id}: "
        f"{response.status_code} {response.text}"
    )


def ensure_beta_build_localizations(
    build_id: str,
    token: str,
    whats_new: str,
    locale: str = "en-US",
    *,
    http_get=None,
    http_post=None,
) -> dict:
    if http_get is None:
        http_get = requests.get
    if http_post is None:
        http_post = requests.post

    headers = {"Authorization": f"Bearer {token}"}
    url = f"{BASE_URL}/builds/{build_id}/betaBuildLocalizations"
    response = http_get(url, headers=headers, timeout=30)

    if response.status_code == 200:
        data = response.json().get("data", [])
        if isinstance(data, list) and data:
            for loc in data:
                attrs = loc.get("attributes", {}) if isinstance(loc, dict) else {}
                if attrs.get("locale") == locale and attrs.get("whatsNew"):
                    return {"status": "exists", "id": loc.get("id", ""), "locale": locale}

    create_url = f"{BASE_URL}/betaBuildLocalizations"
    create_payload = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {
                "locale": locale,
                "whatsNew": whats_new,
            },
            "relationships": {
                "build": {
                    "data": {
                        "type": "builds",
                        "id": build_id,
                    }
                }
            },
        }
    }
    create_headers = {**headers, "Content-Type": "application/json"}
    create_resp = http_post(create_url, headers=create_headers, json=create_payload, timeout=30)

    if create_resp.status_code in (200, 201):
        created = create_resp.json().get("data", {})
        return {"status": "created", "id": created.get("id", ""), "locale": locale}

    if create_resp.status_code == 409:
        return {"status": "exists", "id": "", "locale": locale}

    raise RuntimeError(
        f"Failed to create betaBuildLocalization for build {build_id}: "
        f"{create_resp.status_code} {create_resp.text}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True, help="Apple app ID")
    parser.add_argument("--build-id", required=True, help="ASC build ID")
    parser.add_argument(
        "--whats-new",
        default="Bug fixes and improvements.",
        help="What to Test text for beta build localization",
    )
    parser.add_argument("--locale", default="en-US")
    args = parser.parse_args()

    contact_email = os.getenv("BETA_REVIEW_CONTACT_EMAIL", "")
    contact_first_name = os.getenv("BETA_REVIEW_CONTACT_FIRST_NAME", "")
    contact_last_name = os.getenv("BETA_REVIEW_CONTACT_LAST_NAME", "")
    contact_phone = os.getenv("BETA_REVIEW_CONTACT_PHONE", "")

    try:
        key_id, issuer_id, private_key = get_asc_credentials()
        token = get_asc_token(key_id, issuer_id, private_key)

        review_result = ensure_beta_app_review_detail(
            args.app_id, token,
            contact_email, contact_first_name, contact_last_name, contact_phone,
        )
        loc_result = ensure_beta_build_localizations(
            args.build_id, token, args.whats_new, locale=args.locale,
        )
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)

    if review_result.get("status") == "skipped":
        missing = ", ".join(review_result["missing_fields"])
        print(json.dumps({
            "error": "Beta review contact details are required but missing. "
            f"Set GitHub repository variables: {missing}, "
            "or populate the contact info in App Store Connect.",
        }), file=sys.stderr)
        sys.exit(1)

    print(json.dumps({
        "beta_app_review_detail": review_result,
        "beta_build_localization": loc_result,
    }))


if __name__ == "__main__":
    main()
