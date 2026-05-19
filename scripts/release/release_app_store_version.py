#!/usr/bin/env python3
"""Release a manually held App Store version and clean up TestFlight tags."""

import argparse
import os
import subprocess
import time

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"
RELEASABLE_STATES = {"PENDING_DEVELOPER_RELEASE"}
ALREADY_RELEASED_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}


def get_asc_token(key_id: str, issuer_id: str, private_key_path: str) -> str:
    with open(os.path.expanduser(private_key_path)) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def request(method: str, path: str, token: str, **kwargs) -> requests.Response:
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    if method != "GET":
        headers["Content-Type"] = "application/json"

    resp = requests.request(method, f"{BASE_URL}{path}", headers=headers, timeout=30, **kwargs)
    if not resp.ok:
        raise SystemExit(f"{method} {path} failed ({resp.status_code}): {resp.text}")
    return resp


def find_app_store_version(app_id: str, version: str, token: str) -> dict:
    params = {
        "filter[platform]": "IOS",
        "limit": 50,
        "fields[appStoreVersions]": "versionString,platform,appStoreState",
    }
    resp = request("GET", f"/apps/{app_id}/appStoreVersions", token, params=params)
    for item in resp.json().get("data", []):
        attrs = item.get("attributes", {})
        if attrs.get("versionString") == version and attrs.get("platform") == "IOS":
            return item
    raise SystemExit(f"App Store version {version} for IOS was not found")


def release_version(version_id: str, token: str) -> str:
    payload = {
        "data": {
            "type": "appStoreVersionReleaseRequests",
            "relationships": {
                "appStoreVersion": {
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id,
                    }
                }
            },
        }
    }
    return request("POST", "/appStoreVersionReleaseRequests", token, json=payload).json()["data"]["id"]


def delete_testflight_tags(version: str) -> list[str]:
    pattern = f"testflight/{version}/build-*"
    result = subprocess.run(
        ["git", "tag", "--list", pattern],
        check=True,
        capture_output=True,
        text=True,
    )
    tags = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    for tag in tags:
        subprocess.run(["git", "push", "origin", "--delete", tag], check=True)
    return tags


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key-path", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    token = get_asc_token(args.key_id, args.issuer_id, args.private_key_path)
    version = find_app_store_version(args.app_id, args.version, token)
    state = version["attributes"].get("appStoreState", "")
    version_id = version["id"]
    print(f"Found App Store version {args.version} ({version_id}, state={state})")

    if state in ALREADY_RELEASED_STATES:
        print(f"Version {args.version} is already released; deleting scoped TestFlight tags.")
        if not args.dry_run:
            deleted = delete_testflight_tags(args.version)
            print("Deleted tags: " + (", ".join(deleted) if deleted else "none"))
        return

    if state not in RELEASABLE_STATES:
        raise SystemExit(
            f"Version {args.version} is not releasable yet. "
            f"Expected one of {sorted(RELEASABLE_STATES)}, got {state}."
        )

    if args.dry_run:
        print(f"Dry run: would release version {args.version} and delete testflight/{args.version}/build-* tags.")
        return

    request_id = release_version(version_id, token)
    print(f"Created App Store version release request {request_id}")
    deleted = delete_testflight_tags(args.version)
    print("Deleted tags: " + (", ".join(deleted) if deleted else "none"))


if __name__ == "__main__":
    main()
