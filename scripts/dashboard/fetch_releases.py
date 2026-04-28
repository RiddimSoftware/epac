#!/usr/bin/env python3
"""
Fetch recent GitHub releases and App Store Connect version states.

Writes dashboard/data/releases.json for the project dashboard.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import re
import time
from pathlib import Path

import jwt
import requests

APP_ID = "1224459142"
ASC_BASE = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_REPOSITORY = "RiddimSoftware/epac"
MAX_NOTES_CHARS = 500

STATUS_LABELS = {
    "ACCEPTED": "Accepted",
    "APPROVED": "Approved",
    "DEVELOPER_REJECTED": "Developer Rejected",
    "IN_REVIEW": "In Review",
    "INVALID_BINARY": "Invalid Binary",
    "METADATA_REJECTED": "Metadata Rejected",
    "PENDING_APPLE_RELEASE": "Pending Apple Release",
    "PREPARE_FOR_SUBMISSION": "Preparing Submission",
    "PROCESSING_FOR_APP_STORE": "Processing",
    "READY_FOR_DISTRIBUTION": "On App Store",
    "READY_FOR_REVIEW": "Ready for Review",
    "READY_FOR_SALE": "On App Store",
    "REJECTED": "Rejected",
    "WAITING_FOR_EXPORT_COMPLIANCE": "Waiting for Export Compliance",
    "WAITING_FOR_REVIEW": "Waiting for Review",
}


def get_token(key_id: str, issuer_id: str, key_path: Path) -> str:
    key = key_path.read_text(encoding="utf-8")
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id},
    )


def get_json(url: str, headers: dict | None = None, params: dict | None = None) -> dict:
    response = requests.get(url, headers=headers, params=params, timeout=30)
    response.raise_for_status()
    return response.json()


def fetch_app_store_versions(headers: dict) -> list[dict]:
    data = get_json(
        f"{ASC_BASE}/apps/{APP_ID}/appStoreVersions",
        headers=headers,
        params={
            "limit": 10,
            "fields[appStoreVersions]": "versionString,appStoreState,createdDate",
        },
    )
    versions = []
    for item in data.get("data", []):
        attrs = item.get("attributes", {}) or {}
        version = attrs.get("versionString", "")
        state = attrs.get("appStoreState", "")
        versions.append({
            "version": version,
            "state": state,
            "status_label": status_label(state),
            "created_at": attrs.get("createdDate"),
        })
    return sorted(versions, key=lambda item: item.get("created_at") or "", reverse=True)


def fetch_github_releases(repository: str, token: str | None) -> list[dict]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = get_json(
        f"https://api.github.com/repos/{repository}/releases",
        headers=headers,
        params={"per_page": 10},
    )
    return data if isinstance(data, list) else []


def truncate_notes(body: str | None, limit: int = MAX_NOTES_CHARS) -> str:
    text = (body or "").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def version_from_tag(tag: str) -> str:
    match = re.search(r"\d+(?:\.\d+)+", tag or "")
    return match.group(0) if match else ""


def version_aliases(version: str) -> set[str]:
    aliases = {version} if version else set()
    if version.endswith(".0"):
        aliases.add(version[:-2])
    elif re.fullmatch(r"\d+\.\d+", version):
        aliases.add(f"{version}.0")
    return aliases


def status_label(state: str | None) -> str:
    if not state:
        return "GitHub Release"
    return STATUS_LABELS.get(state, state.replace("_", " ").title())


def merge_releases(github_releases: list[dict], app_versions: list[dict]) -> list[dict]:
    versions_by_number = {}
    for item in app_versions:
        for version in version_aliases(item.get("version", "")):
            versions_by_number[version] = item
    releases = []
    for release in github_releases[:10]:
        tag = release.get("tag_name", "")
        version = version_from_tag(tag)
        app_version = versions_by_number.get(version, {})
        state = app_version.get("state")
        releases.append({
            "tag": tag,
            "name": release.get("name") or tag,
            "version": version,
            "date": release.get("published_at") or release.get("created_at"),
            "notes": truncate_notes(release.get("body")),
            "url": release.get("html_url"),
            "app_store_state": state,
            "status_label": status_label(state),
        })
    return releases


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key", required=True, metavar="PATH", type=Path)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY))
    parser.add_argument("--github-token", default=os.environ.get("GITHUB_TOKEN"))
    parser.add_argument("--output", default=Path("dashboard/data/releases.json"), type=Path)
    args = parser.parse_args()

    asc_token = get_token(args.key_id, args.issuer_id, args.private_key)
    app_versions = fetch_app_store_versions({"Authorization": f"Bearer {asc_token}"})
    github_releases = fetch_github_releases(args.repository, args.github_token)
    releases = merge_releases(github_releases, app_versions)

    output = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "repository": args.repository,
        "app_id": APP_ID,
        "app_store_versions": app_versions,
        "releases": releases,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"  Wrote {args.output} ({len(releases)} releases, {len(app_versions)} ASC versions)")


if __name__ == "__main__":
    main()
