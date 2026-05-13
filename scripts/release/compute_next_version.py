#!/usr/bin/env python3
"""
Compute the next marketing version for an App Store/TestFlight build.

Queries the current live App Store version via the App Store Connect API and
applies a semver bump. It can also prefer an already-created non-live App Store
version train, which lets humans override the automatic bump by creating the
desired next version in App Store Connect before the workflow runs. Falls back
to the latest git tag if no live version exists (first release), and to 0.0.0 if
there are no tags.

Usage:
  python3 compute_next_version.py \
    --key-id S6U297PQHR \
    --issuer-id 69a6de88-... \
    --private-key-path ~/.appstoreconnect/private_keys/AuthKey_S6U297PQHR.p8 \
    --app-id 1224459142 \
    --bump patch|minor|major \
    [--prefer-existing-train] \
    [--output-format github-output]
"""
import argparse
import os
import subprocess
import time
from dataclasses import dataclass

import jwt
import requests


@dataclass(frozen=True)
class AppStoreVersion:
    version: str
    state: str


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


def get_live_version(app_id: str, token: str) -> str | None:
    """Return the current READY_FOR_SALE marketing version, or None if no live version."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"
    params = {
        "filter[platform]": "IOS",
        "filter[appStoreState]": "READY_FOR_SALE",
        "fields[appStoreVersions]": "versionString",
        "limit": 1,
    }
    resp = requests.get(url, headers=headers, params=params, timeout=30)
    resp.raise_for_status()
    data = resp.json().get("data", [])
    return data[0]["attributes"]["versionString"] if data else None


def get_app_store_versions(app_id: str, token: str) -> list[AppStoreVersion]:
    """Return known App Store versions for the app."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"
    params = {
        "filter[platform]": "IOS",
        "fields[appStoreVersions]": "versionString,appStoreState",
        "limit": 200,
    }
    resp = requests.get(url, headers=headers, params=params, timeout=30)
    resp.raise_for_status()

    versions: list[AppStoreVersion] = []
    for item in resp.json().get("data", []):
        attrs = item.get("attributes", {})
        version = attrs.get("versionString")
        state = attrs.get("appStoreState", "")
        if version:
            versions.append(AppStoreVersion(version=version, state=state))
    return versions


def get_latest_git_tag() -> str | None:
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0", "--match", "v*"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip().lstrip("v")
    except subprocess.CalledProcessError:
        return None


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def is_greater_version(candidate: str, current: str) -> bool:
    max_len = max(len(candidate.split(".")), len(current.split(".")))
    candidate_parts = version_key(candidate) + (0,) * max_len
    current_parts = version_key(current) + (0,) * max_len
    return candidate_parts[:max_len] > current_parts[:max_len]


def choose_existing_train(versions: list[AppStoreVersion], current: str) -> str | None:
    candidates = [
        app_version.version
        for app_version in versions
        if app_version.state != "READY_FOR_SALE"
        and is_greater_version(app_version.version, current)
    ]
    if not candidates:
        return None
    return sorted(candidates, key=version_key, reverse=True)[0]


def bump_version(version: str, bump: str) -> str:
    parts = (version.split(".") + ["0", "0"])[:3]
    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
    if bump == "major":
        return f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key-path", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
    parser.add_argument(
        "--prefer-existing-train",
        action="store_true",
        help="Use the highest non-live App Store version greater than the live version before bumping.",
    )
    parser.add_argument("--output-format", choices=["github-output", "text"], default="text")
    args = parser.parse_args()

    token = get_asc_token(args.key_id, args.issuer_id, args.private_key_path)

    current = get_live_version(args.app_id, token)
    source = "App Store Connect (live)"
    if current is None:
        current = get_latest_git_tag()
        source = "latest git tag"
    if current is None:
        current = "0.0.0"
        source = "default (no live version or git tags)"

    train_source = f"{args.bump} bump"
    next_version = None
    if args.prefer_existing_train:
        next_version = choose_existing_train(get_app_store_versions(args.app_id, token), current)
        if next_version:
            train_source = "existing non-live App Store version"

    if next_version is None:
        next_version = bump_version(current, args.bump)

    print(f"Current version ({source}): {current}")
    print(f"Next version ({train_source}): {next_version}")

    if args.output_format == "github-output":
        output_file = os.environ.get("GITHUB_OUTPUT", "/dev/stdout")
        with open(output_file, "a") as f:
            f.write(f"next_version={next_version}\n")
            f.write(f"current_version={current}\n")
            f.write(f"version_source={train_source}\n")
    else:
        print(f"next_version={next_version}")
        print(f"current_version={current}")


if __name__ == "__main__":
    main()
