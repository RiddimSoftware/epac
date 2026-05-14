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
    # When False, the validator receives raw response bytes instead of parsed JSON.
    expect_json: bool = True

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


def validate_search_min_args(status: int, payload: Any) -> None:
    """Anti-regression validator for the 2026-05-14 production failure (no date filters)."""
    if status != 200:
        raise SmokeFailure(f"search:min-args: expected HTTP 200, got {status}")
    body = require_dict(payload, "search:min-args")
    if "error" in body:
        raise SmokeFailure(f"search:min-args: unexpected error key: {body['error']}")
    require_list(body, "search:min-args", "results")


def validate_error_body(endpoint: str, fragment: str) -> Callable[[int, Any], None]:
    """Returns a validator that asserts the response has an error key containing fragment."""
    def _validate(status: int, payload: Any) -> None:
        body = require_dict(payload, endpoint)
        if "error" not in body:
            raise SmokeFailure(f"{endpoint}: expected error key in response body")
        if fragment.lower() not in str(body["error"]).lower():
            raise SmokeFailure(f"{endpoint}: error body does not contain '{fragment}': {body['error']}")
    return _validate


def validate_error_no_stack(endpoint: str) -> Callable[[int, Any], None]:
    """Returns a validator that asserts error body is present and does not leak stack traces."""
    def _validate(status: int, payload: Any) -> None:
        body = require_dict(payload, endpoint)
        if "error" not in body:
            raise SmokeFailure(f"{endpoint}: expected error key in 404 response body")
        error_str = str(body["error"])
        for leak_pattern in ("Traceback", "panic:", "goroutine ", "runtime error"):
            if leak_pattern in error_str:
                raise SmokeFailure(f"{endpoint}: stack trace leaked in error body")
    return _validate


def validate_member_speeches_invalid_page(_: int, payload: Any) -> None:
    body = require_dict(payload, "member-speeches:invalid-page")
    # Accept either 400 with error key, or 200 with total=0
    if "error" in body:
        return
    if "total" in body:
        return
    raise SmokeFailure("member-speeches:invalid-page: expected error key or total field")


def validate_on_this_day_min_args(_: int, payload: Any) -> None:
    """on-this-day with no date param — endpoint uses today's date as default."""
    body = require_dict(payload, "on-this-day:min-args")
    require_keys(body, "on-this-day:min-args", {"date", "items"})
    require_list(body, "on-this-day:min-args", "items")


def validate_calendar(status: int, payload: Any) -> None:
    # payload is raw bytes when expect_json=False
    raw = payload if isinstance(payload, bytes) else b""
    if not raw.lstrip().startswith(b"BEGIN:VCALENDAR"):
        raise SmokeFailure(f"calendar:happy: response body does not start with BEGIN:VCALENDAR")


def validate_openapi(status: int, payload: Any) -> None:
    body = require_dict(payload, "openapi-json")
    if "paths" not in body:
        raise SmokeFailure("openapi-json: response body missing 'paths' key")


CHECKS = [
    # --- health ---
    SmokeCheck(
        name="health:default",
        method="GET",
        path="/health",
        query={},
        expected_statuses={200, 503},
        validator=validate_health,
        deterministic_note="Contract check accepts ok/degraded HealthResponse and catches DB/Lambda error bodies.",
        fixture_note="Pipeline freshness can make this degraded until staging data jobs are seeded and scheduled.",
    ),
    # --- search ---
    SmokeCheck(
        name="search:min-args",
        method="GET",
        path="/search/speeches",
        query={"q": "budget"},
        expected_statuses={200},
        validator=validate_search_min_args,
        deterministic_note="Primary anti-regression check for the 2026-05-14 production failure. No date filters exercises the filter-free SQL path.",
        fixture_note="Result count is data-dependent; empty list is acceptable.",
    ),
    SmokeCheck(
        name="search:all-args",
        method="GET",
        path="/search/speeches",
        query={"q": "housing", "from_date": "2020-01-01", "to_date": "2035-12-31", "user_id": "smoke-test"},
        expected_statuses={200},
        validator=validate_search,
        deterministic_note="Contract check verifies ranked search responds with the expected JSON envelope.",
        fixture_note="Result count is data-dependent; seeded speeches would allow non-empty assertions.",
    ),
    SmokeCheck(
        name="search:empty-query",
        method="GET",
        path="/search/speeches",
        query={"q": ""},
        expected_statuses={400},
        validator=validate_error_body("search:empty-query", "missing 'q'"),
        deterministic_note="Negative check — empty q param must return HTTP 400 with a message referencing 'q'.",
        fixture_note="No fixture required; validates input validation gate.",
    ),
    SmokeCheck(
        name="search:malformed-date",
        method="GET",
        path="/search/speeches",
        query={"q": "health", "from_date": "not-a-date"},
        expected_statuses={400},
        validator=validate_error_body("search:malformed-date", "from_date"),
        deterministic_note="Negative check — invalid from_date must return HTTP 400 with a message referencing 'from_date'.",
        fixture_note="No fixture required; validates date parsing guard.",
    ),
    # --- member speeches ---
    SmokeCheck(
        name="member-speeches:min-args",
        method="GET",
        path="/api/v1/members/0/speeches",
        query={},
        expected_statuses={200},
        validator=validate_member_speeches,
        deterministic_note="Contract check uses a harmless member id with no pagination params.",
        fixture_note="Seeded member/person records would allow an assertion against a known current MP.",
    ),
    SmokeCheck(
        name="member-speeches:all-args",
        method="GET",
        path="/api/v1/members/0/speeches",
        query={"page": "1", "per_page": "10"},
        expected_statuses={200},
        validator=validate_member_speeches,
        deterministic_note="Contract check uses explicit pagination params.",
        fixture_note="Seeded member/person records would allow an assertion against a known current MP.",
    ),
    SmokeCheck(
        name="member-speeches:invalid-page",
        method="GET",
        path="/api/v1/members/0/speeches",
        query={"page": "-1"},
        expected_statuses={400, 200},
        validator=validate_member_speeches_invalid_page,
        deterministic_note="Negative check — page=-1 should return 400 or 200 with total=0. Documents current behavior.",
        fixture_note="No fixture required.",
    ),
    # --- on-this-day ---
    SmokeCheck(
        name="on-this-day:min-args",
        method="GET",
        path="/api/v1/on-this-day",
        query={},
        expected_statuses={200},
        validator=validate_on_this_day_min_args,
        deterministic_note="No date param — endpoint defaults to today's date. Documents and locks expected behavior.",
        fixture_note="Items list will be empty outside active sitting periods.",
    ),
    SmokeCheck(
        name="on-this-day:all-args",
        method="GET",
        path="/api/v1/on-this-day",
        query={"date": "2030-01-01", "limit": "1"},
        expected_statuses={200},
        validator=validate_on_this_day,
        deterministic_note="Contract check uses a fixed date and accepts an empty moments list.",
        fixture_note="Seeded historical speeches would allow a known moment assertion.",
    ),
    SmokeCheck(
        name="on-this-day:invalid-date",
        method="GET",
        path="/api/v1/on-this-day",
        query={"date": "not-a-date"},
        expected_statuses={400},
        validator=validate_error_body("on-this-day:invalid-date", "date"),
        deterministic_note="Negative check — invalid date param must return HTTP 400.",
        fixture_note="No fixture required; validates date parsing guard.",
    ),
    # --- riding boundary ---
    SmokeCheck(
        name="riding-boundary:happy",
        method="GET",
        path="/api/v1/ridings/spadina-harbourfront/boundary",
        query={},
        expected_statuses={200},
        validator=validate_riding_boundary,
        deterministic_note="Contract check uses a 2023 federal riding slug and validates GeoJSON shape.",
        fixture_note="No database fixture required; depends on the upstream Represent boundary provider.",
    ),
    SmokeCheck(
        name="riding-boundary:unknown-slug",
        method="GET",
        path="/api/v1/ridings/this-is-not-a-real-riding-slug/boundary",
        query={},
        expected_statuses={404},
        validator=validate_error_no_stack("riding-boundary:unknown-slug"),
        deterministic_note="Negative check — unknown slug must return HTTP 404 with error body and no stack trace leak.",
        fixture_note="No fixture required.",
    ),
    # --- live status ---
    SmokeCheck(
        name="live-status:default",
        method="GET",
        path="/api/v1/live",
        query={},
        expected_statuses={200},
        validator=validate_live_status,
        deterministic_note="Contract check validates the cached live-status response shape.",
        fixture_note="The exact sitting state is time/data-dependent and is not asserted.",
    ),
    # --- device registration ---
    SmokeCheck(
        name="device-register:missing-token",
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
    SmokeCheck(
        name="device-register:malformed-json",
        method="POST",
        path="/api/v1/device/register",
        query={},
        body=b"not-json",
        headers={"Content-Type": "application/json"},
        expected_statuses={400},
        validator=validate_error_body("device-register:malformed-json", ""),
        deterministic_note="Negative check — malformed JSON body must return HTTP 400 with an error key.",
        fixture_note="No fixture required; validates request parsing guard.",
    ),
    # --- openapi ---
    SmokeCheck(
        name="openapi-json",
        method="GET",
        path="/openapi.json",
        query={},
        expected_statuses={200},
        validator=validate_openapi,
        deterministic_note="Contract check verifies the OpenAPI spec endpoint returns valid JSON with a paths key.",
        fixture_note="No fixture required; catches OpenAPI generation regressions.",
    ),
    # --- additional edge cases to complete the ≥21 matrix ---
    SmokeCheck(
        name="search:future-only",
        method="GET",
        path="/search/speeches",
        query={"q": "senate", "from_date": "2040-01-01"},
        expected_statuses={200},
        validator=validate_search_min_args,
        deterministic_note="Edge case: from_date only (no to_date) with a far-future date. Should return empty results without error.",
        fixture_note="No fixture required; future date guarantees empty results without staging data dependency.",
    ),
    SmokeCheck(
        name="member-speeches:unknown-member",
        method="GET",
        path="/api/v1/members/999999999/speeches",
        query={},
        expected_statuses={200, 404},
        validator=validate_member_speeches_invalid_page,
        deterministic_note="Edge case: large member ID that does not exist. Documents whether the handler returns 200+empty or 404.",
        fixture_note="No fixture required.",
    ),
    SmokeCheck(
        name="on-this-day:far-past",
        method="GET",
        path="/api/v1/on-this-day",
        query={"date": "1985-06-15"},
        expected_statuses={200},
        validator=validate_on_this_day,
        deterministic_note="Edge case: a 1985 date exercises the handler against historical data that predates the app's primary corpus.",
        fixture_note="Items list is data-dependent; empty list is acceptable.",
    ),
    # --- calendar ---
    SmokeCheck(
        name="calendar:happy",
        method="GET",
        path="/api/v1/calendar/house.ics",
        query={},
        expected_statuses={200},
        validator=validate_calendar,
        expect_json=False,
        deterministic_note="Contract check verifies the iCal endpoint returns a valid VCALENDAR body.",
        fixture_note="No fixture required; calendar is generated from the parliamentary schedule.",
    ),
]


def fetch_response(check: SmokeCheck, base_url: str) -> tuple[int, Any]:
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

    if not check.expect_json:
        return status, raw

    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise SmokeFailure(f"{check.name}: response is not valid JSON: {error}") from error

    return status, payload


def run_check(check: SmokeCheck, base_url: str) -> tuple[bool, str]:
    last_error = ""
    for attempt in range(1, RETRIES + 1):
        try:
            status, payload = fetch_response(check, base_url)
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
