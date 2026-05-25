#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import jwt
import requests

DEFAULT_LOOKUP_TIMEOUT_SECONDS = 20 * 60
DEFAULT_POLL_INTERVAL_SECONDS = 30


def get_asc_secret():
    env = os.environ.copy()
    env["AWS_PROFILE"] = os.environ.get("AWS_PROFILE", "riddim-agent")
    res = subprocess.run(
        [
            "aws", "secretsmanager", "get-secret-value",
            "--secret-id", "appstore/connect-api",
            "--region", "us-east-1",
            "--query", "SecretString",
            "--output", "text"
        ],
        check=True,
        capture_output=True,
        text=True,
        env=env
    )
    secret = json.loads(res.stdout)
    return secret["key_id"], secret["issuer_id"], secret.get("key") or secret.get("private_key")


def get_asc_credentials():
    key_id = os.getenv("ASC_KEY_ID")
    issuer_id = os.getenv("ASC_ISSUER_ID")
    private_key = os.getenv("ASC_PRIVATE_KEY")

    if key_id and issuer_id and private_key:
        return key_id, issuer_id, private_key

    key_path = os.getenv("ASC_KEY_PATH")
    if key_id and issuer_id and key_path:
        return key_id, issuer_id, Path(os.path.expanduser(key_path)).read_text(encoding="utf-8")

    return get_asc_secret()


def get_token(key_id, issuer_id, key):
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": key_id})


def build_query_params(app_id, build_number):
    return {
        "filter[app]": app_id,
        "filter[version]": build_number,
        "fields[builds]": "version,processingState,preReleaseVersion",
        "include": "preReleaseVersion",
        "limit": 50,
        "sort": "-uploadedDate"
    }


def find_matching_build_id(payload, marketing_version):
    version_map = {
        inc["id"]: inc["attributes"]["version"]
        for inc in payload.get("included", [])
        if inc.get("type") == "preReleaseVersions"
    }

    for build in payload.get("data", []):
        pre_release_id = (
            build.get("relationships", {})
            .get("preReleaseVersion", {})
            .get("data", {})
            .get("id")
        )
        if version_map.get(pre_release_id) == marketing_version:
            return build["id"]

    return None


def resolve_build_id(
    app_id,
    marketing_version,
    build_number,
    token,
    timeout_seconds=DEFAULT_LOOKUP_TIMEOUT_SECONDS,
    poll_interval_seconds=DEFAULT_POLL_INTERVAL_SECONDS,
    current_time=None,
    sleep=None,
    get_fn=None,
):
    if current_time is None:
        current_time = time.time
    if sleep is None:
        sleep = time.sleep
    if get_fn is None:
        get_fn = requests.get

    headers = {"Authorization": f"Bearer {token}"}
    url = "https://api.appstoreconnect.apple.com/v1/builds"
    params = build_query_params(app_id, build_number)
    start = current_time()
    attempt = 1

    while True:
        response = get_fn(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        build_id = find_matching_build_id(response.json(), marketing_version)
        if build_id:
            return build_id

        elapsed = current_time() - start
        if elapsed >= timeout_seconds:
            return None

        print(
            f"Build not found yet (attempt {attempt}; elapsed {int(elapsed)}s/"
            f"{int(timeout_seconds)}s). Waiting {poll_interval_seconds}s...",
            flush=True,
        )
        attempt += 1
        sleep(max(0, poll_interval_seconds))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument(
        "--timeout-minutes",
        type=float,
        default=DEFAULT_LOOKUP_TIMEOUT_SECONDS / 60,
        help="Maximum time to wait for ASC build lookup visibility (default: 20)",
    )
    parser.add_argument(
        "--poll-interval-seconds",
        type=float,
        default=DEFAULT_POLL_INTERVAL_SECONDS,
        help="Polling period while waiting for build lookup visibility (default: 30)",
    )
    args = parser.parse_args()

    timeout_seconds = int(args.timeout_minutes * 60)
    poll_interval_seconds = int(args.poll_interval_seconds)
    if timeout_seconds <= 0:
        print("timeout-minutes must be > 0")
        sys.exit(1)
    if poll_interval_seconds <= 0:
        print("poll-interval-seconds must be > 0")
        sys.exit(1)

    key_id, issuer_id, key = get_asc_credentials()
    token = get_token(key_id, issuer_id, key)

    build_id = resolve_build_id(
        args.app_id,
        args.version,
        args.build_number,
        token,
        timeout_seconds=timeout_seconds,
        poll_interval_seconds=poll_interval_seconds,
    )
    if build_id:
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a") as f:
                f.write(f"build_id={build_id}\n")
        print(build_id)
        sys.exit(0)

    print(
        "Build not found after waiting "
        f"{timeout_seconds}s for version {args.version} build {args.build_number}."
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
