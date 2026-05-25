#!/usr/bin/env python3
"""Submit a TestFlight build for Apple Beta App Review."""

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
ASC_SECRET_ID = "appstore/connect-api"
ASC_SECRET_REGION = "us-east-1"


class BuildNotProcessedError(RuntimeError):
    pass


class SubmissionError(RuntimeError):
    pass


def get_asc_secret() -> dict:
    """Fetch ASC API credentials from AWS Secrets Manager."""
    result = subprocess.run(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            ASC_SECRET_ID,
            "--region",
            ASC_SECRET_REGION,
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
    key_path = os.getenv("ASC_KEY_PATH")
    private_key = os.getenv("ASC_PRIVATE_KEY")

    if key_id and issuer_id and private_key:
        return key_id, issuer_id, private_key

    if key_id and issuer_id and key_path:
        return key_id, issuer_id, Path(os.path.expanduser(key_path)).read_text(encoding="utf-8")

    secret = get_asc_secret()
    return secret["key_id"], secret["issuer_id"], secret["private_key"]


def get_asc_token(key_id: str, issuer_id: str, private_key: str) -> str:
    """Generate a short-lived JWT for ASC API authentication."""
    import time

    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def _parse_payload(response: requests.Response, fallback_status: int | None = None) -> dict:
    if response.text:
        try:
            payload = response.json()
            if isinstance(payload, dict):
                return payload
            return {"value": payload}
        except json.JSONDecodeError:
            return {"message": response.text}

    if fallback_status is not None:
        return {"status_code": fallback_status}
    return {"status_code": response.status_code}


def _submission_output(submission: dict, build_id: str) -> dict[str, str]:
    attrs = submission.get("attributes", {}) if isinstance(submission, dict) else {}
    return {
        "submission_id": str(submission.get("id", "")) if isinstance(submission, dict) else "",
        "build_id": build_id,
        "review_state": str(attrs.get("betaReviewState", "")) if isinstance(attrs, dict) else "",
    }


def fetch_existing_submission(build_id: str, token: str) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{BASE_URL}/builds/{build_id}/betaAppReviewSubmission"
    try:
        response = requests.get(url, headers=headers, timeout=30)
    except requests.RequestException as exc:
        raise SubmissionError(f"Failed to fetch existing submission for build {build_id}: {exc}") from exc

    if response.status_code != 200:
        if response.status_code == 404:
            raise SubmissionError(
                f"No beta App Review submission found for build {build_id}. "
                "Call submit_beta_app_review again after submitting the build first."
            )
        raise SubmissionError(
            f"Failed to fetch existing submission for build {build_id} "
            f"({response.status_code}): {response.text}"
        )

    payload = _parse_payload(response)
    submission = payload.get("data") if isinstance(payload, dict) else None
    if not submission:
        raise SubmissionError(f"Unexpected payload while fetching build {build_id} submission: {payload}")
    if isinstance(submission, list):
        if not submission:
            raise SubmissionError(f"No beta App Review submission record returned for build {build_id}")
        return submission[0]
    return submission


def submit_beta_app_review(build_id: str, token: str) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    url = f"{BASE_URL}/betaAppReviewSubmissions"
    payload = {
        "data": {
            "type": "betaAppReviewSubmissions",
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

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
    except requests.RequestException as exc:
        raise SubmissionError(f"Failed to POST beta review submission for build {build_id}: {exc}") from exc

    if response.status_code in (200, 201):
        payload = _parse_payload(response)
        submission = payload.get("data")
        if not submission:
            raise SubmissionError(
                f"Submission accepted for build {build_id} but response had no submission record: {payload}"
            )
        return _submission_output(submission, build_id)

    if response.status_code == 409:
        submission = fetch_existing_submission(build_id, token)
        return _submission_output(submission, build_id)

    if response.status_code == 422:
        payload = _parse_payload(response, fallback_status=422)
        detail = ""
        errors = payload.get("errors") if isinstance(payload, dict) else None
        if isinstance(errors, list) and errors:
            detail = f" {errors[0].get('detail') if isinstance(errors[0], dict) else errors[0]}"
        raise BuildNotProcessedError(
            "ASC rejected the submission with 422: build not ready for review." + detail +
            " Call wait_for_build_processed.py before retrying."
        )

    raise SubmissionError(
        f"Submission failed for build {build_id} ({response.status_code}): {response.text}"
    )


DEFAULT_MAX_RETRIES = 5
DEFAULT_RETRY_INTERVAL_SECONDS = 30


def submit_with_retry(
    build_id: str,
    token: str,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_interval_seconds: int = DEFAULT_RETRY_INTERVAL_SECONDS,
    sleep_fn: callable = None,
) -> dict[str, str]:
    if sleep_fn is None:
        from time import sleep as sleep_fn

    last_error = None
    total_attempts = 1 + max_retries
    for attempt in range(total_attempts):
        try:
            return submit_beta_app_review(build_id, token)
        except BuildNotProcessedError as exc:
            last_error = exc
            if attempt < max_retries:
                print(
                    f"Attempt {attempt + 1}/{total_attempts}: build not ready. "
                    f"Retrying in {retry_interval_seconds}s...",
                    file=sys.stderr,
                )
                sleep_fn(retry_interval_seconds)

    raise last_error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--max-retries", type=int, default=DEFAULT_MAX_RETRIES)
    parser.add_argument("--retry-interval-seconds", type=int, default=DEFAULT_RETRY_INTERVAL_SECONDS)
    args = parser.parse_args()

    try:
        key_id, issuer_id, private_key = get_asc_credentials()
        token = get_asc_token(key_id, issuer_id, private_key)
        record = submit_with_retry(
            args.build_id,
            token,
            max_retries=args.max_retries,
            retry_interval_seconds=args.retry_interval_seconds,
        )
    except BuildNotProcessedError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(4)
    except SubmissionError as exc:
        print(f"Failed to submit build {args.build_id}: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"Unhandled error while submitting build {args.build_id}: {exc}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(record))


if __name__ == "__main__":
    main()
