#!/usr/bin/env python3
"""Smoke-test the deployed EPAC staging backend API.

The checks intentionally assert response contract shape instead of seeded record
counts. Several endpoints depend on staging database contents that are not yet
fixture-managed, so empty result sets are acceptable when the JSON schema is
still recognizable.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable


DEFAULT_BASE_URL = "https://staging-api.epac.riddimsoftware.com"
TIMEOUT_SECONDS = 20
RETRIES = 3


class SmokeFailure(Exception):
    """Raised when an endpoint response does not match its smoke contract."""


@dataclass(frozen=True)
class SmokeCheck:
    name: str
    method: str
    path: str
    query: dict[str, str]
    expected_statuses: set[int]
    validator: Callable[[int, Any], None]
    body: bytes | None = None
    headers: dict[str, str] | None = None
    deterministic_note: str = ""
    fixture_note: str = ""

    def url(self, base_url: str) -> str:
        base = base_url.rstrip("/")
        query = urllib.parse.urlencode(self.query)
        suffix = f"?{query}" if query else ""
        return f"{base}{self.path}{suffix}"


def require_dict(payload: Any, endpoint: str) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise SmokeFailure(f"{endpoint}: response body must be a JSON object")
    return payload


def require_keys(payload: dict[str, Any], endpoint: str, keys: set[str]) -> None:
    missing = sorted(keys - payload.keys())
    if missing:
        raise SmokeFailure(f"{endpoint}: missing keys: {', '.join(missing)}")


def require_list(payload: dict[str, Any], endpoint: str, key: str) -> None:
    if not isinstance(payload.get(key), list):
        raise SmokeFailure(f"{endpoint}: {key} must be an array")


def validate_health(status: int, payload: Any) -> None:
    body = require_dict(payload, "health")
    require_keys(body, "health", {"status", "checked_at", "pipelines"})
    if body["status"] not in {"ok", "degraded"}:
        raise SmokeFailure("health: status must be ok or degraded")
    require_list(body, "health", "pipelines")
    if status == 503 and "error" in body:
        raise SmokeFailure("health: 503 error body indicates storage or Lambda failure")


def validate_search(_: int, payload: Any) -> None:
    body = require_dict(payload, "search")
    require_keys(body, "search", {"query", "language_hint", "results"})
    require_list(body, "search", "results")


def validate_member_speeches(_: int, payload: Any) -> None:
    body = require_dict(payload, "member speeches")
    require_keys(body, "member speeches", {"member_id", "page", "per_page", "total", "pages", "stats", "speeches"})
    require_list(body, "member speeches", "speeches")
    if not isinstance(body["stats"], dict):
        raise SmokeFailure("member speeches: stats must be an object")


def validate_on_this_day(_: int, payload: Any) -> None:
    body = require_dict(payload, "on-this-day")
    require_keys(body, "on-this-day", {"date", "items"})
    require_list(body, "on-this-day", "items")


def validate_riding_boundary(_: int, payload: Any) -> None:
    body = require_dict(payload, "riding boundary")
    require_keys(body, "riding boundary", {"slug", "name", "external_id", "geometry", "source_url"})
    geometry = body["geometry"]
    if not isinstance(geometry, dict):
        raise SmokeFailure("riding boundary: geometry must be an object")
    require_keys(geometry, "riding boundary geometry", {"type", "coordinates"})


def validate_live_status(_: int, payload: Any) -> None:
    body = require_dict(payload, "live status")
    require_keys(body, "live status", {"status", "is_sitting", "business_type", "checked_at", "source_url"})
    if not isinstance(body["is_sitting"], bool):
        raise SmokeFailure("live status: is_sitting must be a boolean")


def validate_device_register(status: int, payload: Any) -> None:
    body = require_dict(payload, "device registration")
    require_keys(body, "device registration", {"error"})
    if "token" not in str(body["error"]).lower():
        raise SmokeFailure("device registration: safe invalid request must reject missing token")
    if status != 400:
        raise SmokeFailure("device registration: safe invalid request must return HTTP 400")


CHECKS = [
    SmokeCheck(
        name="health",
        method="GET",
        path="/health",
        query={},
        expected_statuses={200, 503},
        validator=validate_health,
        deterministic_note="Contract check accepts ok/degraded HealthResponse and catches DB/Lambda error bodies.",
        fixture_note="Pipeline freshness can make this degraded until staging data jobs are seeded and scheduled.",
    ),
    SmokeCheck(
        name="search",
        method="GET",
        path="/search/speeches",
        query={"q": "housing", "from_date": "2020-01-01", "to_date": "2035-12-31"},
        expected_statuses={200},
        validator=validate_search,
        deterministic_note="Contract check verifies ranked search responds with the expected JSON envelope.",
        fixture_note="Result count is data-dependent; seeded speeches would allow non-empty assertions.",
    ),
    SmokeCheck(
        name="member speeches",
        method="GET",
        path="/api/v1/members/0/speeches",
        query={"page": "1", "per_page": "1"},
        expected_statuses={200},
        validator=validate_member_speeches,
        deterministic_note="Contract check uses a harmless member id and accepts an empty speech page.",
        fixture_note="Seeded member/person records would allow an assertion against a known current MP.",
    ),
    SmokeCheck(
        name="on-this-day",
        method="GET",
        path="/api/v1/on-this-day",
        query={"date": "2030-01-01", "limit": "1"},
        expected_statuses={200},
        validator=validate_on_this_day,
        deterministic_note="Contract check uses a fixed date and accepts an empty moments list.",
        fixture_note="Seeded historical speeches would allow a known moment assertion.",
    ),
    SmokeCheck(
        name="riding boundary",
        method="GET",
        path="/api/v1/ridings/spadina-harbourfront/boundary",
        query={},
        expected_statuses={200},
        validator=validate_riding_boundary,
        deterministic_note="Contract check uses a 2023 federal riding slug and validates GeoJSON shape.",
        fixture_note="No database fixture required; depends on the upstream Represent boundary provider.",
    ),
    SmokeCheck(
        name="live status",
        method="GET",
        path="/api/v1/live",
        query={},
        expected_statuses={200},
        validator=validate_live_status,
        deterministic_note="Contract check validates the cached live-status response shape.",
        fixture_note="The exact sitting state is time/data-dependent and is not asserted.",
    ),
    SmokeCheck(
        name="device registration",
        method="POST",
        path="/api/v1/device/register",
        query={},
        body=b"{}",
        headers={"Content-Type": "application/json"},
        expected_statuses={400},
        validator=validate_device_register,
        deterministic_note="Safe negative contract check confirms invalid registration is rejected before writing data.",
        fixture_note="A successful 200 registration requires a test APNs token fixture and cleanup policy.",
    ),
]


def fetch_json(check: SmokeCheck, base_url: str) -> tuple[int, Any]:
    headers = {
        "Accept": "application/json",
        "User-Agent": "epac-staging-smoke/1.0",
        "X-Device-ID": "epac-staging-smoke",
    }
    headers.update(check.headers or {})
    request = urllib.request.Request(
        check.url(base_url),
        data=check.body,
        headers=headers,
        method=check.method,
    )

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        raw = error.read()
    except urllib.error.URLError as error:
        raise SmokeFailure(f"{check.name}: request failed: {error}") from error

    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise SmokeFailure(f"{check.name}: response is not valid JSON: {error}") from error

    return status, payload


def run_check(check: SmokeCheck, base_url: str) -> tuple[bool, str]:
    last_error = ""
    for attempt in range(1, RETRIES + 1):
        try:
            status, payload = fetch_json(check, base_url)
            if status not in check.expected_statuses:
                expected = ", ".join(str(code) for code in sorted(check.expected_statuses))
                raise SmokeFailure(f"{check.name}: expected HTTP {expected}, got {status}")
            check.validator(status, payload)
            return True, f"HTTP {status}"
        except SmokeFailure as error:
            last_error = str(error)
            if attempt < RETRIES:
                time.sleep(attempt * 2)
    return False, last_error


def write_summary(base_url: str, results: list[tuple[SmokeCheck, bool, str]]) -> None:
    lines = [
        "## Backend staging smoke tests",
        "",
        f"Base URL: `{base_url}`",
        "",
        "| Endpoint | Result | Evidence |",
        "| --- | --- | --- |",
    ]
    for check, passed, evidence in results:
        icon = "PASS" if passed else "FAIL"
        lines.append(f"| {check.name} | {icon} | {evidence} |")

    lines.extend(["", "### Deterministic and fixture-dependent coverage", ""])
    for check, _, _ in results:
        lines.append(f"- **{check.name}:** {check.deterministic_note} {check.fixture_note}")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    print("\n".join(lines))


def list_checks() -> None:
    for check in CHECKS:
        query = f"?{urllib.parse.urlencode(check.query)}" if check.query else ""
        print(f"{check.method} {check.path}{query} - {check.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run EPAC staging backend smoke tests.")
    parser.add_argument("--base-url", default=os.environ.get("STAGING_API_BASE_URL", DEFAULT_BASE_URL))
    parser.add_argument("--list", action="store_true", help="List configured checks without making network calls.")
    args = parser.parse_args()

    if args.list:
        list_checks()
        return 0

    base_url = args.base_url.rstrip("/")
    failures = 0
    results: list[tuple[SmokeCheck, bool, str]] = []
    for check in CHECKS:
        passed, evidence = run_check(check, base_url)
        results.append((check, passed, evidence))
        if passed:
            print(f"PASS {check.name}: {evidence}")
        else:
            failures += 1
            print(f"FAIL {check.name}: {evidence}", file=sys.stderr)

    write_summary(base_url, results)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
