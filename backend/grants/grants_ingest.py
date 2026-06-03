#!/usr/bin/env python3
"""Fetch TBS Proactive Disclosure – Grants and Contributions and emit grants.json.

Source (authoritative, official):
- https://open.canada.ca/data/en/dataset/432527ab-7aac-45b5-81d6-7597107a7013

The output JSON is consumed by the iOS app as a bundled snapshot for the current
and prior fiscal year.  Re-run quarterly after TBS publishes new disclosure data
and commit the updated file alongside any iOS PR that ships it to users.

Riding attribution: many grants list only a recipient city or postal code.
Full postal-code-to-riding geocoding is out of scope for this script; records
include `recipient_province_en` which the iOS client uses for province-level
filtering.  A follow-up task (Human Handoff gate) will spot-check riding totals
against the raw dataset before production use.

Usage:
    python3 grants_ingest.py [--fiscal-year 2024-2025]
    python3 grants_ingest.py --help
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


CKAN_API_BASE = "https://open.canada.ca/data/api/action/datastore_search"
# Stable CKAN resource ID for TBS Proactive Disclosure – Grants and Contributions.
RESOURCE_ID = "1d15a62f-5656-49ad-8c88-f40ce689d831"
DATASET_URL = "https://open.canada.ca/data/en/dataset/432527ab-7aac-45b5-81d6-7597107a7013"
PIPELINE_NAME = "grants_ingest"
DEFAULT_PAGE_SIZE = 1000
REQUEST_TIMEOUT = 30


class _JSONFormatter(logging.Formatter):
    """Stdlib-only JSON log formatter."""

    _RESERVED = {
        "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
        "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
        "created", "msecs", "relativeCreated", "thread", "threadName",
        "processName", "process", "message", "taskName",
    }

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": PIPELINE_NAME,
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key in self._RESERVED or key in payload:
                continue
            payload[key] = value
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def _configure_logging() -> logging.Logger:
    logger = logging.getLogger(PIPELINE_NAME)
    if logger.handlers:
        return logger
    handler = logging.StreamHandler(stream=sys.stderr)
    handler.setFormatter(_JSONFormatter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


logger = _configure_logging()


@dataclass
class GrantRecord:
    id: str
    recipient_name: str
    amount: float
    department: str
    purpose: str
    recipient_city: str
    recipient_province: str
    recipient_type: str
    fiscal_year: str
    agreement_date: str


@dataclass
class GrantsSnapshot:
    version: int = 1
    as_of_date: str = ""
    fiscal_years: list = field(default_factory=list)
    source: dict = field(default_factory=dict)
    records: list = field(default_factory=list)


def _current_fiscal_years() -> list[str]:
    now = datetime.now(tz=timezone.utc)
    year = now.year
    month = now.month
    # Canadian fiscal year: April 1 – March 31.
    current_start = year if month >= 4 else year - 1
    return [
        f"{current_start}-{current_start + 1}",
        f"{current_start - 1}-{current_start}",
    ]


def _fetch_page(fiscal_year: str, offset: int, limit: int = DEFAULT_PAGE_SIZE) -> dict:
    """Fetch one page of grants from the CKAN Datastore API."""
    params = {
        "resource_id": RESOURCE_ID,
        "limit": limit,
        "offset": offset,
        "filters": json.dumps({"fiscal_year": fiscal_year}),
        "sort": "agreement_value desc NULLS LAST",
    }
    url = f"{CKAN_API_BASE}?{urlencode(params)}"
    request = Request(url, headers={"Accept": "application/json"})
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError) as exc:
        logger.error("HTTP error fetching grants", extra={"url": url, "error": str(exc)})
        raise


def _parse_record(raw: dict) -> Optional[GrantRecord]:
    ref_number = raw.get("ref_number", "").strip()
    if not ref_number:
        return None
    recipient = (raw.get("recipient_name_en") or "").strip()
    if not recipient:
        return None
    value_str = raw.get("agreement_value", "0") or "0"
    try:
        amount = float(value_str)
    except ValueError:
        amount = 0.0
    if amount <= 0:
        return None

    department = (raw.get("owner_org_title") or "").strip()
    purpose = ((raw.get("proj_name_en") or raw.get("prog_name_en")) or "").strip()
    city = (raw.get("recipient_city_en") or "").strip()
    province = (raw.get("recipient_province_en") or "").strip()
    recipient_type = (raw.get("recipient_type_en") or "").strip()
    fiscal_year = (raw.get("fiscal_year") or "").strip()
    agreement_date = (
        raw.get("expected_date") or raw.get("agreement_start_date") or ""
    ).strip()

    return GrantRecord(
        id=ref_number,
        recipient_name=recipient,
        amount=amount,
        department=department,
        purpose=purpose,
        recipient_city=city,
        recipient_province=province,
        recipient_type=recipient_type,
        fiscal_year=fiscal_year,
        agreement_date=agreement_date,
    )


def fetch_grants_for_fiscal_year(fiscal_year: str) -> list[GrantRecord]:
    """Paginate through all grants for the given fiscal year."""
    records: list[GrantRecord] = []
    offset = 0
    total: Optional[int] = None

    logger.info("Fetching grants", extra={"fiscal_year": fiscal_year})
    while True:
        time.sleep(0.25)  # polite crawl delay
        response = _fetch_page(fiscal_year, offset)
        result = response.get("result", {})
        if total is None:
            total = result.get("total", 0)
            logger.info("Total records", extra={"fiscal_year": fiscal_year, "total": total})

        raw_records = result.get("records", [])
        if not raw_records:
            break

        for raw in raw_records:
            parsed = _parse_record(raw)
            if parsed:
                records.append(parsed)

        offset += len(raw_records)
        if offset >= (total or 0):
            break

    logger.info(
        "Fetched grants",
        extra={"fiscal_year": fiscal_year, "records_kept": len(records), "total_fetched": offset},
    )
    return records


def build_snapshot(fiscal_years: list[str]) -> GrantsSnapshot:
    all_records: list[GrantRecord] = []
    for fy in fiscal_years:
        all_records.extend(fetch_grants_for_fiscal_year(fy))

    return GrantsSnapshot(
        version=1,
        as_of_date=datetime.now(tz=timezone.utc).strftime("%Y-%m-%d"),
        fiscal_years=fiscal_years,
        source={
            "name": "Treasury Board Secretariat Proactive Disclosure – Grants and Contributions",
            "url": DATASET_URL,
            "resource_id": RESOURCE_ID,
        },
        records=[asdict(r) for r in all_records],
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--fiscal-year",
        help="Specific fiscal year to fetch (e.g. 2024-2025). Defaults to current + prior year.",
    )
    args = parser.parse_args()

    fiscal_years = [args.fiscal_year] if args.fiscal_year else _current_fiscal_years()
    logger.info("Starting grants ingest", extra={"fiscal_years": fiscal_years})

    snapshot = build_snapshot(fiscal_years)
    print(json.dumps(asdict(snapshot), ensure_ascii=False, indent=2))
    logger.info(
        "Ingest complete",
        extra={"total_records": len(snapshot.records), "fiscal_years": fiscal_years},
    )


if __name__ == "__main__":
    main()
