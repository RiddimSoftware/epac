#!/usr/bin/env python3
"""Ensure an App Store version train exists and attach a TestFlight build."""

import argparse
import os
import time

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"


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


def find_app_store_version(app_id: str, version: str, token: str) -> dict | None:
    params = {
        "filter[app]": app_id,
        "filter[platform]": "IOS",
        "limit": 50,
        "fields[appStoreVersions]": "versionString,platform,appStoreState",
    }
    resp = request("GET", "/appStoreVersions", token, params=params)
    for item in resp.json().get("data", []):
        attrs = item.get("attributes", {})
        if attrs.get("versionString") == version and attrs.get("platform") == "IOS":
            return item
    return None


def create_app_store_version(app_id: str, version: str, token: str) -> dict:
    payload = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version,
            },
            "relationships": {
                "app": {
                    "data": {
                        "type": "apps",
                        "id": app_id,
                    }
                }
            },
        }
    }
    return request("POST", "/appStoreVersions", token, json=payload).json()["data"]


def attach_build(version_id: str, build_id: str, token: str) -> None:
    payload = {
        "data": {
            "type": "builds",
            "id": build_id,
        }
    }
    request("PATCH", f"/appStoreVersions/{version_id}/relationships/build", token, json=payload)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key-path", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-id", required=True)
    args = parser.parse_args()

    token = get_asc_token(args.key_id, args.issuer_id, args.private_key_path)
    version = find_app_store_version(args.app_id, args.version, token)
    if version:
        print(
            "Found App Store version "
            f"{args.version} ({version['id']}, state={version['attributes'].get('appStoreState')})"
        )
    else:
        version = create_app_store_version(args.app_id, args.version, token)
        print(f"Created App Store version {args.version} ({version['id']})")

    attach_build(version["id"], args.build_id, token)
    print(f"Attached build {args.build_id} to App Store version {args.version}")


if __name__ == "__main__":
    main()
