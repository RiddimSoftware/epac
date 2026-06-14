#!/usr/bin/env python3
"""Smoke-test the deployed EPAC backend API.

The checks intentionally assert response contract shape instead of seeded record
counts. Several endpoints depend on database contents that are not yet
fixture-managed, so empty result sets are acceptable when the JSON schema is
still recognizable. Artifact-backed list endpoints with canonical public data
are stricter and must return non-empty lists.

Checks are filtered at runtime against the deployment manifest
(backend/manifest/deployment-services.json). A check whose ``service`` field
names a service that is not deployed to the selected environment is skipped
automatically, so the script stays correct as services are added or removed
without requiring a code change. Checks with ``service=None`` always run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, Callable


DEFAULT_BASE_URLS = {
    "staging": "https://staging-api.epac.riddimsoftware.com",
    "production": "https://api.epac.riddimsoftware.com",
}
TIMEOUT_SECONDS = 20
RETRIES = 3
C11_BILL_ID = "C-11"
C11_FIRST_READING_VERSION_ID = "c-11-13615955-first-reading"
C11_COMMITTEE_VERSION_ID = "c-11-13896514-as-amended-by-committee"
C10_BILL_ID = "C-10"
C10_FIRST_READING_VERSION_ID = "c-10-13610716-first-reading"


def supports_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR") or os.environ.get("GITHUB_ACTIONS") == "true":
        return True
    return sys.stdout.isatty()


class Color:
    GREEN = "\033[92m" if supports_color() else ""
    RED = "\033[91m" if supports_color() else ""
    YELLOW = "\033[93m" if supports_color() else ""
    CYAN = "\033[96m" if supports_color() else ""
    BOLD = "\033[1m" if supports_color() else ""
    RESET = "\033[0m" if supports_color() else ""


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
    kind: str = "http"
    # Manifest service name this check belongs to. None = always run regardless
    # of which services are deployed. Set to a service name to skip automatically
    # when that service has deploy.<environment>=false in the manifest.
    service: str | None = None
    # Full checks require known seeded/backfilled data and are skipped in the
    # default contract mode.
    full_only: bool = False

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


def require_non_empty_list(payload: dict[str, Any], endpoint: str, key: str) -> None:
    require_list(payload, endpoint, key)
    if len(payload[key]) == 0:
        raise SmokeFailure(f"{endpoint}: {key} must not be empty")


def validate_health(status: int, payload: Any) -> None:
    body = require_dict(payload, "health")
    require_keys(body, "health", {"status", "checked_at", "pipelines"})
    if body["status"] not in {"ok", "degraded"}:
        raise SmokeFailure("health: status must be ok or degraded")
    require_list(body, "health", "pipelines")
    if status == 503 and "error" in body:
        raise SmokeFailure("health: 503 error body indicates storage or Lambda failure")


def validate_bills(_: int, payload: Any) -> None:
    body = require_dict(payload, "bills")
    require_keys(body, "bills", {"bills"})
    require_non_empty_list(body, "bills", "bills")


def is_api_gateway_not_found(status: int, payload: Any) -> bool:
    return (
        status == 404
        and isinstance(payload, dict)
        and payload.get("message") == "Not Found"
        and "error" not in payload
    )


def validate_bill_diff_route(status: int, payload: Any) -> None:
    body = require_dict(payload, "bills:diff-route")
    if is_api_gateway_not_found(status, body):
        raise SmokeFailure("bills:diff-route: API Gateway returned Not Found; route is missing or unsynced")
    if status != 400:
        raise SmokeFailure(f"bills:diff-route: expected service-owned HTTP 400 for missing from/to, got {status}")
    if "error" not in body:
        raise SmokeFailure("bills:diff-route: service-owned 400 response missing error key")
    error_text = str(body["error"]).lower()
    for required in ("from", "to"):
        if required not in error_text:
            raise SmokeFailure(
                f"bills:diff-route: error body does not mention missing {required!r}: {body['error']}"
            )


def validate_bill_diff_payload(status: int, payload: Any) -> None:
    body = require_dict(payload, "bills:diff-full")
    if is_api_gateway_not_found(status, body):
        raise SmokeFailure("bills:diff-full: API Gateway returned Not Found; route is missing or unsynced")
    if status != 200:
        raise SmokeFailure(f"bills:diff-full: expected HTTP 200 seeded diff payload, got {status}")
    require_keys(body, "bills:diff-full", {"from", "to", "clauses"})
    for key in ("from", "to"):
        version = body[key]
        if not isinstance(version, dict) or not isinstance(version.get("id"), str) or not version["id"]:
            raise SmokeFailure(f"bills:diff-full: {key} version must include a non-empty id")
    require_non_empty_list(body, "bills:diff-full", "clauses")


def validate_bill_diff_unavailable(status: int, payload: Any) -> None:
    if status != 204:
        raise SmokeFailure(f"bills:diff-one-version: expected HTTP 204 unavailable diff, got {status}")
    if payload != b"":
        raise SmokeFailure("bills:diff-one-version: 204 response body must be empty")


def validate_bill_diff_unknown(status: int, payload: Any) -> None:
    body = require_dict(payload, "bills:diff-unknown")
    if is_api_gateway_not_found(status, body):
        raise SmokeFailure("bills:diff-unknown: API Gateway returned Not Found; route is missing or unsynced")
    if "error" not in body:
        raise SmokeFailure(
            "bills:diff-unknown: expected service-owned error body (key 'error'), got keys: "
            + (", ".join(sorted(body)) or "none")
        )
    if status == 404 and "not found" not in str(body["error"]).lower():
        raise SmokeFailure(
            f"bills:diff-unknown: 404 body is not a documented not-found message: {body['error']}"
        )


def validate_members(_: int, payload: Any) -> None:
    body = require_dict(payload, "members")
    require_keys(body, "members", {"members"})
    require_non_empty_list(body, "members", "members")


def validate_member_speeches(_: int, payload: Any) -> None:
    body = require_dict(payload, "member speeches")
    require_keys(body, "member speeches", {"member_id", "page", "per_page", "total", "pages", "stats", "speeches"})
    require_list(body, "member speeches", "speeches")
    if not isinstance(body["stats"], dict):
        raise SmokeFailure("member speeches: stats must be an object")


def validate_member_votes(_: int, payload: Any) -> None:
    body = require_dict(payload, "member votes")
    require_keys(body, "member votes", {"member_id", "page", "per_page", "total", "pages", "votes"})
    require_list(body, "member votes", "votes")


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


def validate_estimates(_: int, payload: Any) -> None:
    body = require_dict(payload, "estimates")
    require_keys(body, "estimates", {"estimates"})
    require_list(body, "estimates", "estimates")


def validate_config(_: int, payload: Any) -> None:
    body = require_dict(payload, "config")
    require_keys(body, "config", {"minimum_supported_version", "features"})
    if not isinstance(body["features"], dict):
        raise SmokeFailure("config: features must be an object")


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


def validate_member_speeches_invalid_page(status: int, payload: Any) -> None:
    body = require_dict(payload, "member-speeches:invalid-page")
    # Accept 400 with error key, or 200 with total strictly equal to 0
    if status == 400:
        if "error" not in body:
            raise SmokeFailure("member-speeches:invalid-page: HTTP 400 response missing error key")
        return
    if "total" not in body:
        raise SmokeFailure("member-speeches:invalid-page: HTTP 200 response missing total field")
    if body["total"] != 0:
        raise SmokeFailure(f"member-speeches:invalid-page: expected total=0 for page=-1, got {body['total']}")


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


def validate_hansard_search(status: int, payload: Any) -> None:
    body = require_dict(payload, "hansard-search")
    if status == 503:
        if "error" not in body:
            raise SmokeFailure("hansard-search: 503 response missing error key")
        body["_smoke_evidence"] = f"HTTP 503 ({body['error']})"
        return

    require_keys(body, "hansard-search", {"page", "per_page", "total", "results"})
    require_list(body, "hansard-search", "results")
    if body["page"] != 1:
        raise SmokeFailure(f"hansard-search: page = {body['page']!r}, want 1")
    if body["per_page"] != 1:
        raise SmokeFailure(f"hansard-search: per_page = {body['per_page']!r}, want 1")


def validate_cabinet_lobbying_overview(_: int, payload: Any) -> None:
    body = require_dict(payload, "cabinet-lobbying-overview")
    require_keys(body, "cabinet-lobbying-overview", {"parliament", "citation", "source_url", "ministers"})
    if body["parliament"] != 45:
        raise SmokeFailure(f"cabinet-lobbying-overview: parliament = {body['parliament']!r}, want 45")
    require_list(body, "cabinet-lobbying-overview", "ministers")


def validate_lobbyist_organization_directory(_: int, payload: Any) -> None:
    body = require_dict(payload, "lobbyist-organizations")
    require_keys(body, "lobbyist-organizations", {"page", "per_page", "citation", "source_url", "rows"})
    if body["page"] != 1:
        raise SmokeFailure(f"lobbyist-organizations: page = {body['page']!r}, want 1")
    if body["per_page"] != 1:
        raise SmokeFailure(f"lobbyist-organizations: per_page = {body['per_page']!r}, want 1")
    require_list(body, "lobbyist-organizations", "rows")


def validate_hansard_search_manifest(status: int, payload: Any) -> None:
    if status == 404:
        return
    body = require_dict(payload, "hansard-search-manifest")
    require_keys(
        body,
        "hansard-search-manifest",
        {"version", "sitting_count", "sqlite_sha256"},
    )
    if body["version"] != "v1":
        raise SmokeFailure(f"hansard-search-manifest: version = {body['version']!r}, want 'v1'")
    if not isinstance(body["sitting_count"], int) or body["sitting_count"] < 0:
        raise SmokeFailure("hansard-search-manifest: sitting_count must be a non-negative integer")
    if not isinstance(body["sqlite_sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", body["sqlite_sha256"]):
        raise SmokeFailure("hansard-search-manifest: sqlite_sha256 must be a 64-character lowercase hex string")


CHECKS = [
    # --- health ---
    SmokeCheck(
        name="health:default",
        method="GET",
        path="/health",
        query={},
        expected_statuses={200, 503},
        validator=validate_health,
        service="health",
        deterministic_note="Contract check accepts ok/degraded HealthResponse and catches DB/Lambda error bodies.",
        fixture_note="Pipeline freshness can make this degraded until staging data jobs are seeded and scheduled.",
    ),
    # --- artifact-backed parliamentary data ---
    SmokeCheck(
        name="bills:list",
        method="GET",
        path="/api/v1/bills",
        query={},
        expected_statuses={200},
        validator=validate_bills,
        service="bills",
        deterministic_note="Contract check verifies the bills list endpoint is backed by a non-empty published artifact.",
        fixture_note="No fixture required; the current Parliament bills dataset should not be empty after ingestion.",
    ),
    SmokeCheck(
        name="bills:diff-route",
        method="GET",
        path="/api/v1/bills/C-8/diff",
        query={},
        expected_statuses={400, 404},
        validator=validate_bill_diff_route,
        service="bills",
        deterministic_note="Route-reachability check omits from/to so the bills service returns its own HTTP 400 before diff data is required.",
        fixture_note="No backfilled diff fixture required; API Gateway 404 is treated as a route exposure failure.",
    ),
    SmokeCheck(
        name="bills:diff-unknown",
        method="GET",
        path="/api/v1/bills/ZZ-9999/diff",
        query={"from": "v1", "to": "v2"},
        expected_statuses={404, 503},
        validator=validate_bill_diff_unknown,
        service="bills",
        deterministic_note="Negative check — an unknown bill id with from/to set drives the bills service's own application-level 404 ('bill not found'), proving the route reaches the Lambda and is distinguished from an API Gateway route-missing 404.",
        fixture_note="No backfilled diff data required; an unknown bill returns 404 before any version/diff lookup. HTTP 503 is tolerated while the bills index warms.",
    ),
    SmokeCheck(
        name="bills:diff-full",
        method="GET",
        path=f"/api/v1/bills/{C11_BILL_ID}/diff",
        query={"from": C11_FIRST_READING_VERSION_ID, "to": C11_COMMITTEE_VERSION_ID},
        expected_statuses={200},
        validator=validate_bill_diff_payload,
        service="bills",
        deterministic_note="Full-mode check asserts a seeded current-Parliament multi-version bill returns a concrete diff payload.",
        fixture_note="Requires C-11 diff data to be backfilled in the selected environment; skipped unless --mode full is used.",
        full_only=True,
    ),
    SmokeCheck(
        name="bills:diff-one-version",
        method="GET",
        path=f"/api/v1/bills/{C10_BILL_ID}/diff",
        query={"from": C10_FIRST_READING_VERSION_ID, "to": C10_FIRST_READING_VERSION_ID},
        expected_statuses={204},
        validator=validate_bill_diff_unavailable,
        service="bills",
        deterministic_note="Full-mode negative check asserts a real one-version bill returns the documented unavailable diff response.",
        fixture_note="Requires C-10 version metadata to be backfilled in the selected environment; skipped unless --mode full is used.",
        expect_json=False,
        full_only=True,
    ),
    SmokeCheck(
        name="members:list",
        method="GET",
        path="/api/v1/members",
        query={},
        expected_statuses={200},
        validator=validate_members,
        service="members",
        deterministic_note="Contract check verifies the members list endpoint is backed by a non-empty published artifact.",
        fixture_note="No fixture required; the House member dataset should not be empty after ingestion.",
    ),
    # --- hansard search index manifest (S3) ---
    SmokeCheck(
        name="hansard-search-manifest",
        method="S3",
        path="hansard-search/v1/manifest.json",
        query={},
        expected_statuses={200, 404},
        validator=validate_hansard_search_manifest,
        service="hansard-search-index",
        deterministic_note="Contract check validates the v1 manifest envelope and SHA-256 format when the index has been generated.",
        fixture_note="The first deploy may not have a manifest until an operator runs the manual reindex; HTTP 404 is reported as a skip warning.",
        kind="s3-hansard-search-manifest",
    ),
    # --- member speeches ---
    SmokeCheck(
        name="member-speeches:min-args",
        method="GET",
        path="/api/v1/members/0/speeches",
        query={},
        expected_statuses={200},
        validator=validate_member_speeches,
        service="member-speeches",
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
        service="member-speeches",
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
        service="member-speeches",
        deterministic_note="Negative check — page=-1 should return 400 or 200 with total=0. Documents current behavior.",
        fixture_note="No fixture required.",
    ),
    # --- member votes ---
    SmokeCheck(
        name="member-votes:min-args",
        method="GET",
        path="/api/v1/members/0/votes",
        query={},
        expected_statuses={200},
        validator=validate_member_votes,
        service="member-votes",
        deterministic_note="Contract check uses a harmless member id with no pagination params.",
        fixture_note="Seeded member vote artifacts would allow an assertion against a known current MP.",
    ),
    SmokeCheck(
        name="member-votes:all-args",
        method="GET",
        path="/api/v1/members/0/votes",
        query={"page": "1", "per_page": "10"},
        expected_statuses={200},
        validator=validate_member_votes,
        service="member-votes",
        deterministic_note="Contract check uses explicit pagination params.",
        fixture_note="Seeded member vote artifacts would allow an assertion against a known current MP.",
    ),
    # --- on-this-day ---
    SmokeCheck(
        name="on-this-day:min-args",
        method="GET",
        path="/api/v1/on-this-day",
        query={},
        expected_statuses={200},
        validator=validate_on_this_day_min_args,
        service="on-this-day",
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
        service="on-this-day",
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
        service="on-this-day",
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
        service="riding-boundary",
        deterministic_note="Contract check uses a 2023 federal riding slug and validates GeoJSON shape.",
        fixture_note="No database fixture required; response is served from the published S3 boundary artifact.",
    ),
    SmokeCheck(
        name="riding-boundary:unknown-slug",
        method="GET",
        path="/api/v1/ridings/this-is-not-a-real-riding-slug/boundary",
        query={},
        expected_statuses={404},
        validator=validate_error_no_stack("riding-boundary:unknown-slug"),
        service="riding-boundary",
        deterministic_note="Negative check — unknown slug must return HTTP 404 with error body and no stack trace leak.",
        fixture_note="No fixture required.",
    ),
    # --- estimates ---
    SmokeCheck(
        name="estimates:fiscal-year",
        method="GET",
        path="/api/v1/estimates",
        query={"fiscal_year": "2024-25"},
        expected_statuses={200},
        validator=validate_estimates,
        service="estimates",
        deterministic_note="Contract check verifies the fiscal-year filter returns the estimates envelope.",
        fixture_note="Result count depends on the published estimates artifact; empty list is acceptable.",
    ),
    SmokeCheck(
        name="estimates:missing-filter",
        method="GET",
        path="/api/v1/estimates",
        query={},
        expected_statuses={400},
        validator=validate_error_body("estimates:missing-filter", "missing"),
        service="estimates",
        deterministic_note="Negative check — estimates list requires fiscal_year unless an org id is in the path.",
        fixture_note="No fixture required; validates input validation gate.",
    ),
    # --- config ---
    SmokeCheck(
        name="config:default",
        method="GET",
        path="/api/v1/config",
        query={},
        expected_statuses={200},
        validator=validate_config,
        service="config",
        deterministic_note="Contract check verifies the app config artifact response shape.",
        fixture_note="Feature flag values are release-config dependent and not asserted.",
    ),
    # --- openapi ---
    SmokeCheck(
        name="openapi-json",
        method="GET",
        path="/openapi.json",
        query={},
        expected_statuses={200},
        validator=validate_openapi,
        service="openapi",
        deterministic_note="Contract check verifies the OpenAPI spec endpoint returns valid JSON with a paths key.",
        fixture_note="No fixture required; catches OpenAPI generation regressions.",
    ),
    # --- hansard search ---
    SmokeCheck(
        name="hansard-search",
        method="GET",
        path="/api/v1/hansard/search",
        query={"q": "test", "per_page": "1"},
        expected_statuses={200, 503},
        validator=validate_hansard_search,
        service="hansard-search",
        deterministic_note="Contract check validates the Hansard search response envelope; HTTP 503 is accepted until the index is generated in staging.",
        fixture_note="Result count is data-dependent and may be zero even after the index exists.",
    ),
    # --- lobbying screens ---
    SmokeCheck(
        name="cabinet-lobbying-overview",
        method="GET",
        path="/api/v1/cabinet/lobbying-overview",
        query={"parliament": "45"},
        expected_statuses={200},
        validator=validate_cabinet_lobbying_overview,
        service="lobbying",
        deterministic_note="Contract check exercises the Accountability > Cabinet Lobbying screen endpoint.",
        fixture_note="Minister count is data-dependent, but the response envelope must be available after a staging reindex.",
    ),
    SmokeCheck(
        name="lobbyist-organizations:directory",
        method="GET",
        path="/api/v1/lobbying/organizations",
        query={"page": "1", "per_page": "1"},
        expected_statuses={200},
        validator=validate_lobbyist_organization_directory,
        service="lobbying",
        deterministic_note="Contract check exercises the Accountability > Lobbyist Organizations directory endpoint.",
        fixture_note="Directory row count is data-dependent, but the response envelope must be available after a staging reindex.",
    ),
    SmokeCheck(
        name="member-speeches:unknown-member",
        method="GET",
        path="/api/v1/members/999999999/speeches",
        query={},
        expected_statuses={200, 404},
        validator=validate_member_speeches_invalid_page,
        service="member-speeches",
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
        service="on-this-day",
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
        service="calendar",
        deterministic_note="Contract check verifies the iCal endpoint returns a valid VCALENDAR body.",
        fixture_note="No fixture required; calendar is generated from the parliamentary schedule.",
    ),
]


def load_deployed_services(manifest_path: Path, environment: str) -> set[str]:
    """Return the set of service names with deploy.<environment>=true in the manifest."""
    try:
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
        return {
            svc["name"]
            for svc in manifest.get("services", [])
            if svc.get("deploy", {}).get(environment, False)
        }
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        print(f"Warning: could not read manifest at {manifest_path}: {exc}. Running all checks.", file=sys.stderr)
        return {check.service for check in CHECKS if check.service is not None}


def parse_service_filter(raw: str) -> set[str] | None:
    raw = raw.strip()
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {part.strip() for part in raw.split(",") if part.strip()}
    if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
        raise SmokeFailure("--services must be a JSON string array or a comma-separated list")
    return {item.strip() for item in parsed if item.strip()}


def _default_manifest_path() -> Path:
    """Resolve manifest path relative to the repo root (two levels above this script)."""
    return Path(__file__).resolve().parent.parent.parent / "backend" / "manifest" / "deployment-services.json"


def fetch_response(check: SmokeCheck, base_url: str) -> tuple[int, Any]:
    if check.kind == "s3-hansard-search-manifest":
        return fetch_hansard_search_manifest()

    headers = {
        "Accept": "application/json",
        "User-Agent": "epac-backend-smoke/1.0",
        "X-Device-ID": "epac-backend-smoke",
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


def fetch_hansard_search_manifest() -> tuple[int, Any]:
    bucket = first_env(
        "EPAC_ARTIFACT_BUCKET_STAGING",
        "EPAC_ARTIFACT_BUCKET",
        "ARTIFACTS_BUCKET",
        "ARTIFACT_BUCKET",
    )
    prefix = os.environ.get("EPAC_HANSARD_SEARCH_PREFIX", "hansard-search/v1").strip().strip("/")
    key = f"{prefix}/manifest.json"
    if not bucket:
        return 404, {"_smoke_evidence": "SKIP artifact bucket not configured"}

    with NamedTemporaryFile(delete=False) as handle:
        output_path = handle.name
    try:
        result = subprocess.run(
            ["aws", "s3api", "get-object", "--bucket", bucket, "--key", key, output_path],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            stderr = result.stderr or result.stdout
            if any(fragment in stderr for fragment in ("NoSuchKey", "Not Found", "404", "NoSuchBucket")):
                return 404, {"_smoke_evidence": f"SKIP s3://{bucket}/{key} not found"}
            raise SmokeFailure(f"hansard-search-manifest: aws s3api get-object failed: {stderr.strip()}")
        with open(output_path, "r", encoding="utf-8") as manifest_file:
            return 200, json.load(manifest_file)
    except FileNotFoundError as error:
        raise SmokeFailure("hansard-search-manifest: aws CLI is not installed") from error
    finally:
        try:
            os.unlink(output_path)
        except OSError:
            pass


def first_env(*names: str) -> str:
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


def run_check(check: SmokeCheck, base_url: str) -> tuple[bool, str]:
    last_error = ""
    for attempt in range(1, RETRIES + 1):
        try:
            status, payload = fetch_response(check, base_url)
            if status not in check.expected_statuses:
                expected = ", ".join(str(code) for code in sorted(check.expected_statuses))
                raise SmokeFailure(f"{check.name}: expected HTTP {expected}, got {status}")
            check.validator(status, payload)
            if isinstance(payload, dict) and "_smoke_evidence" in payload:
                return True, str(payload["_smoke_evidence"])
            return True, f"HTTP {status}"
        except SmokeFailure as error:
            last_error = str(error)
            if attempt < RETRIES:
                time.sleep(attempt * 2)
    return False, last_error


def write_summary(
    base_url: str,
    environment: str,
    results: list[tuple[SmokeCheck, bool, str]],
    skipped: list[SmokeCheck],
) -> None:
    lines = [
        f"## Backend {environment} smoke tests",
        "",
        f"Base URL: `{base_url}`",
        "",
        "| Endpoint | Result | Evidence |",
        "| --- | --- | --- |",
    ]
    for check, passed, evidence in results:
        icon = "PASS" if passed else "FAIL"
        lines.append(f"| {check.name} | {icon} | {evidence} |")
    for check in skipped:
        lines.append(f"| {check.name} | SKIP | service `{check.service}` not selected for this {environment} smoke run |")

    lines.extend(["", "### Deterministic and fixture-dependent coverage", ""])
    for check, _, _ in results:
        lines.append(f"- **{check.name}:** {check.deterministic_note} {check.fixture_note}")
    for check in skipped:
        lines.append(f"- **{check.name}:** *(skipped - `{check.service}` was not selected for this {environment} smoke run)*")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")

    failures = sum(1 for _, passed, _ in results if not passed)
    print()
    print(f"{Color.BOLD}Backend {environment} smoke tests summary:{Color.RESET}")
    print(f"  Base URL: {base_url}")
    print(f"  Checks: {len(results)} active, {len(skipped)} skipped")
    
    passed_count = len(results) - failures
    print(f"  Passed: {Color.GREEN if passed_count > 0 else ''}{passed_count}{Color.RESET}")
    print(f"  Failed: {Color.RED if failures > 0 else ''}{failures}{Color.RESET}")
    
    if failures > 0:
        print()
        print(f"{Color.BOLD}{Color.RED}Failed checks:{Color.RESET}")
        for check, passed, evidence in results:
            if not passed:
                print(f"  - {Color.RED}{check.name}{Color.RESET}: {evidence}")


def list_checks() -> None:
    for check in CHECKS:
        query = f"?{urllib.parse.urlencode(check.query)}" if check.query else ""
        svc = f" [{check.service}]" if check.service else " [always]"
        mode = " [full]" if check.full_only else ""
        print(f"{check.method} {check.path}{query} - {check.name}{svc}{mode}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run EPAC backend smoke tests.")
    parser.add_argument(
        "--environment",
        choices=("staging", "production"),
        default=os.environ.get("EPAC_BACKEND_SMOKE_ENVIRONMENT", "staging"),
    )
    parser.add_argument("--base-url", default=None)
    parser.add_argument("--list", action="store_true", help="List configured checks without making network calls.")
    parser.add_argument(
        "--manifest",
        default=None,
        help="Path to deployment-services.json. Defaults to backend/manifest/deployment-services.json at the repo root.",
    )
    parser.add_argument(
        "--services",
        default=os.environ.get("EPAC_BACKEND_SMOKE_SERVICES", os.environ.get("EPAC_STAGING_SMOKE_SERVICES", "")),
        help="JSON array or comma-separated service names to smoke. Defaults to manifest services with deploy.<environment>=true.",
    )
    parser.add_argument(
        "--mode",
        choices=("contract", "full"),
        default=os.environ.get("EPAC_BACKEND_SMOKE_MODE", "contract"),
        help="contract runs fixture-light checks; full also runs seeded/backfilled data assertions.",
    )
    args = parser.parse_args()

    if args.list:
        list_checks()
        return 0

    manifest_path = Path(args.manifest) if args.manifest else _default_manifest_path()
    deployed_services = load_deployed_services(manifest_path, args.environment)
    service_filter = parse_service_filter(args.services)
    if service_filter is not None:
        deployed_services &= service_filter

    mode_checks = [c for c in CHECKS if args.mode == "full" or not c.full_only]
    active_checks = [c for c in mode_checks if c.service is None or c.service in deployed_services]
    skipped_checks = [c for c in mode_checks if c.service is not None and c.service not in deployed_services]

    if not active_checks:
        print(f"{Color.RED}Error: No active staging smoke checks remain after service filtering.{Color.RESET}", file=sys.stderr)
        return 1

    if skipped_checks:
        skipped_names = ", ".join(c.name for c in skipped_checks)
        print(
            f"{Color.YELLOW}Skipping {len(skipped_checks)} check(s) for services not deployed to {args.environment}:{Color.RESET} {skipped_names}",
            file=sys.stderr,
        )

    default_base_url = DEFAULT_BASE_URLS[args.environment]
    base_url = (args.base_url or os.environ.get("STAGING_API_BASE_URL" if args.environment == "staging" else "PRODUCTION_API_BASE_URL") or default_base_url).rstrip("/")
    failures = 0
    results: list[tuple[SmokeCheck, bool, str]] = []
    for check in active_checks:
        passed, evidence = run_check(check, base_url)
        results.append((check, passed, evidence))
        if passed:
            print(f"{Color.GREEN}PASS{Color.RESET} {check.name}: {evidence}")
        else:
            failures += 1
            print(f"{Color.RED}FAIL{Color.RESET} {check.name}: {evidence}", file=sys.stderr)

    write_summary(base_url, args.environment, results, skipped_checks)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
