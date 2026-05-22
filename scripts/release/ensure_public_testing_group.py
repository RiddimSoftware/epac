#!/usr/bin/env python3
"""Create the epac PublicTesting TestFlight group and submit the first beta review."""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, TextIO

import jwt
import requests


BASE_URL = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_GROUP_NAME = "PublicTesting"
DEFAULT_WHATS_NEW = "Tonight's build from AI Tinkerers Toronto Science Fair"
REVIEW_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED", "REJECTED"}


class ASCAPIError(Exception):
    def __init__(
        self,
        *,
        step: str,
        method: str,
        path: str,
        status_code: int | None,
        response: Any,
    ):
        super().__init__(f"{step} failed")
        self.step = step
        self.method = method
        self.path = path
        self.status_code = status_code
        self.response = response


class SetupError(Exception):
    def __init__(self, *, step: str, message: str, response: Any | None = None):
        super().__init__(message)
        self.step = step
        self.response = response


class ASCClient:
    def __init__(self, token: str):
        self.token = token

    def request(
        self,
        method: str,
        path: str,
        step: str,
        *,
        allow_statuses: set[int] | None = None,
        **kwargs: Any,
    ) -> Any:
        headers = kwargs.pop("headers", {})
        headers["Authorization"] = f"Bearer {self.token}"
        if method != "GET":
            headers["Content-Type"] = "application/json"

        response = requests.request(
            method,
            f"{BASE_URL}{path}",
            headers=headers,
            timeout=30,
            **kwargs,
        )
        if response.status_code in (allow_statuses or set()):
            return None
        if not response.ok:
            raise ASCAPIError(
                step=step,
                method=method,
                path=path,
                status_code=response.status_code,
                response=parse_response(response),
            )
        if response.status_code == 204 or not response.text.strip():
            return {}
        return response.json()


def parse_response(response: requests.Response) -> Any:
    try:
        return response.json()
    except ValueError:
        return response.text


def get_asc_token(key_id: str, issuer_id: str, private_key_path: str) -> str:
    private_key = Path(os.path.expanduser(private_key_path)).read_text(encoding="utf-8")
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def load_credentials_from_aws() -> tuple[str, str, str]:
    env = {**os.environ, "AWS_PROFILE": os.environ.get("AWS_PROFILE", "riddim-agent")}
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
    key_id = secret["key_id"]
    issuer_id = secret["issuer_id"]
    key_dir = Path.home() / ".appstoreconnect" / "private_keys"
    key_dir.mkdir(parents=True, exist_ok=True)
    key_path = key_dir / f"AuthKey_{key_id}.p8"
    key_path.write_text(secret["private_key"], encoding="utf-8")
    key_path.chmod(0o600)
    return key_id, issuer_id, str(key_path)


def find_app(client: Any, bundle_id: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        "/apps",
        "list_apps",
        params={"filter[bundleId]": bundle_id, "limit": 1, "fields[apps]": "bundleId,name"},
    )
    apps = response.get("data", [])
    if not apps:
        raise SetupError(
            step="find_app",
            message=f"No App Store Connect app found for bundle id {bundle_id}",
            response=response,
        )
    return apps[0]


def find_or_create_group(client: Any, app_id: str, group_name: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        f"/apps/{app_id}/betaGroups",
        "list_beta_groups",
        params={
            "limit": 200,
            "fields[betaGroups]": "name,publicLinkEnabled,publicLinkLimitEnabled",
        },
    )
    for group in response.get("data", []):
        if group.get("attributes", {}).get("name") == group_name:
            return group

    payload = {
        "data": {
            "type": "betaGroups",
            "attributes": {
                "name": group_name,
                "publicLinkEnabled": False,
                "publicLinkLimitEnabled": False,
                "feedbackEnabled": True,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    }
    return client.request("POST", "/betaGroups", "create_beta_group", json=payload)["data"]


def latest_valid_build(client: Any, app_id: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        "/builds",
        "list_valid_builds",
        params={
            "filter[app]": app_id,
            "filter[processingState]": "VALID",
            "sort": "-uploadedDate",
            "limit": 50,
            "fields[builds]": "version,uploadedDate,processingState,preReleaseVersion",
            "include": "preReleaseVersion",
        },
    )
    builds = sorted(
        response.get("data", []),
        key=lambda item: item.get("attributes", {}).get("uploadedDate", ""),
        reverse=True,
    )
    if not builds:
        raise SetupError(
            step="find_latest_valid_build",
            message="No VALID TestFlight builds found for app",
            response=response,
        )
    build = builds[0]
    version_map = {
        item["id"]: item.get("attributes", {}).get("version", "unknown")
        for item in response.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }
    pre_release_id = (
        build.get("relationships", {})
        .get("preReleaseVersion", {})
        .get("data", {})
        .get("id", "")
    )
    build["_resolved_version"] = version_map.get(pre_release_id, "unknown")
    return build


def ensure_beta_app_localizations(client: Any, app_id: str) -> None:
    response = client.request(
        "GET",
        f"/apps/{app_id}/betaAppLocalizations",
        "list_beta_app_localizations",
        params={
            "limit": 200,
            "fields[betaAppLocalizations]": "locale,description",
        },
    )
    localizations = response.get("data", [])
    if not localizations:
        payload = {
            "data": {
                "type": "betaAppLocalizations",
                "attributes": {
                    "locale": "en-US",
                    "description": DEFAULT_WHATS_NEW,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                },
            }
        }
        client.request("POST", "/betaAppLocalizations", "create_beta_app_localization", json=payload)
        return

    for localization in localizations:
        attrs = localization.get("attributes", {})
        if attrs.get("description"):
            continue
        payload = {
            "data": {
                "type": "betaAppLocalizations",
                "id": localization["id"],
                "attributes": {
                    "description": DEFAULT_WHATS_NEW,
                },
            }
        }
        client.request(
            "PATCH",
            f"/betaAppLocalizations/{localization['id']}",
            "update_beta_app_localization",
            json=payload,
        )


def ensure_beta_build_localization(client: Any, build_id: str) -> None:
    response = client.request(
        "GET",
        f"/builds/{build_id}/betaBuildLocalizations",
        "list_beta_build_localizations",
        params={"limit": 200, "fields[betaBuildLocalizations]": "locale,whatsNew"},
    )
    for localization in response.get("data", []):
        if localization.get("attributes", {}).get("locale") == "en-US":
            return

    payload = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {
                "locale": "en-US",
                "whatsNew": DEFAULT_WHATS_NEW,
            },
            "relationships": {
                "build": {"data": {"type": "builds", "id": build_id}},
            },
        }
    }
    client.request("POST", "/betaBuildLocalizations", "create_beta_build_localization", json=payload)


def attach_build_to_group(client: Any, group_id: str, build_id: str) -> None:
    payload = {"data": [{"type": "builds", "id": build_id}]}
    client.request(
        "POST",
        f"/betaGroups/{group_id}/relationships/builds",
        "attach_build_to_group",
        json=payload,
        allow_statuses={409},
    )


def review_status_for_build(client: Any, build_id: str) -> str | None:
    response = client.request(
        "GET",
        f"/builds/{build_id}/betaAppReviewSubmission",
        "get_beta_app_review_submission",
        params={"fields[betaAppReviewSubmissions]": "betaReviewState,submittedDate"},
        allow_statuses={404},
    )
    if not response:
        return None
    data = response.get("data")
    if not isinstance(data, dict):
        return None
    state = data.get("attributes", {}).get("betaReviewState")
    return state if state in REVIEW_STATES else state or None


def submit_beta_review(client: Any, build_id: str) -> str:
    payload = {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {"data": {"type": "builds", "id": build_id}},
            },
        }
    }
    response = client.request(
        "POST",
        "/betaAppReviewSubmissions",
        "create_beta_app_review_submission",
        json=payload,
        allow_statuses={409},
    )
    if not response:
        return "WAITING_FOR_REVIEW"
    return response.get("data", {}).get("attributes", {}).get("betaReviewState", "WAITING_FOR_REVIEW")


def ensure_public_testing_group(
    client: Any,
    *,
    bundle_id: str,
    group_name: str,
    dry_run: bool,
) -> dict[str, str]:
    if dry_run:
        return dry_run_summary(group_name)

    app = find_app(client, bundle_id)
    group = find_or_create_group(client, app["id"], group_name)
    build = latest_valid_build(client, app["id"])
    build_id = build["id"]

    ensure_beta_app_localizations(client, app["id"])
    ensure_beta_build_localization(client, build_id)
    attach_build_to_group(client, group["id"], build_id)
    review_status = review_status_for_build(client, build_id)
    if not review_status:
        review_status = submit_beta_review(client, build_id)

    return {
        "group_id": group["id"],
        "group_name": group.get("attributes", {}).get("name", group_name),
        "build_id": build_id,
        "build_version": build.get("_resolved_version", "unknown"),
        "review_status": review_status,
    }


def dry_run_summary(group_name: str) -> dict[str, Any]:
    return {
        "dry_run": True,
        "planned_api_calls": [
            "GET /v1/apps?filter[bundleId]=<bundle-id>",
            "GET /v1/apps/<app-id>/betaGroups; select name=" + group_name,
            "POST /v1/betaGroups if the group is missing",
            "GET /v1/builds?filter[processingState]=VALID&sort=-uploadedDate",
            "GET /v1/apps/<app-id>/betaAppLocalizations",
            "PATCH /v1/betaAppLocalizations/<id> if description is missing",
            "GET /v1/builds/<build-id>/betaBuildLocalizations",
            "POST /v1/betaBuildLocalizations if en-US is missing",
            "POST /v1/betaGroups/<group-id>/relationships/builds",
            "GET /v1/builds/<build-id>/betaAppReviewSubmission",
            "POST /v1/betaAppReviewSubmissions if missing",
        ],
    }


def handle_error(error: Exception, *, stderr: TextIO = sys.stderr) -> int:
    if isinstance(error, ASCAPIError):
        payload = {
            "error": "asc_api_error",
            "step": error.step,
            "method": error.method,
            "path": error.path,
            "status_code": error.status_code,
            "response": error.response,
        }
    elif isinstance(error, SetupError):
        payload = {
            "error": "setup_error",
            "step": error.step,
            "message": str(error),
            "response": error.response,
        }
    else:
        payload = {
            "error": "unexpected_error",
            "step": "unexpected",
            "message": f"{type(error).__name__}: {error}",
        }
    print(json.dumps(payload, sort_keys=True), file=stderr)
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--group-name", default=DEFAULT_GROUP_NAME)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--key-id", default="")
    parser.add_argument("--issuer-id", default="")
    parser.add_argument("--private-key-path", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.dry_run:
            summary = ensure_public_testing_group(
                client=None,
                bundle_id=args.bundle_id,
                group_name=args.group_name,
                dry_run=True,
            )
        else:
            key_id = args.key_id
            issuer_id = args.issuer_id
            private_key_path = args.private_key_path
            if not (key_id and issuer_id and private_key_path):
                key_id, issuer_id, private_key_path = load_credentials_from_aws()
            token = get_asc_token(key_id, issuer_id, private_key_path)
            summary = ensure_public_testing_group(
                ASCClient(token),
                bundle_id=args.bundle_id,
                group_name=args.group_name,
                dry_run=False,
            )
        print(json.dumps(summary, sort_keys=True))
        return 0
    except Exception as error:
        return handle_error(error)


if __name__ == "__main__":
    sys.exit(main())
