#!/usr/bin/env python3
"""Fetch ministerial travel and hospitality disclosures from TBS proactive disclosure pages.

Sources (authoritative, official):
- Treasury Board Secretariat Proactive Disclosure: https://www.canada.ca/en/treasury-board-secretariat/services/access-information-privacy/access-information/proactive-disclosure.html
- Each federal institution publishes quarterly travel and hospitality data at its own
  proactive-disclosure URL. The department registry below lists the known institutions.

Data is published quarterly, typically within 60 days after each quarter ends. Field formats
vary by department; this script normalises all records to a common schema before writing output.

The output JSON is consumed by the iOS app (ios/epac/ministerial-expenses.json) as a bundled
snapshot. Re-run this script quarterly (or when new Cabinet members are confirmed) and commit
the updated file alongside the iOS PR that ships it to users.

Usage:
    python3 ministerial_ingest.py [--output PATH] [--dry-run] [--quarters N] [--departments FILE]
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import logging
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timezone
from typing import Any, Iterator, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PIPELINE_NAME = "ministerial_ingest"
TBS_BASE_URL = "https://www.canada.ca/en/treasury-board-secretariat"

# Registry of departments that publish ministerial travel and hospitality data.
# Each entry maps a slug to the HTML landing page that links to quarterly CSVs.
# The URL pattern follows the Open Government Proactive Disclosure Directive.
DEPARTMENT_REGISTRY: list[dict[str, str]] = [
    {
        "slug": "finance",
        "name": "Finance Canada",
        "travel_url": "https://www.canada.ca/en/department-finance/corporate/proactive-disclosure/travel.html",
        "hospitality_url": "https://www.canada.ca/en/department-finance/corporate/proactive-disclosure/hospitality.html",
    },
    {
        "slug": "globalaffairs",
        "name": "Global Affairs Canada",
        "travel_url": "https://www.international.gc.ca/transparence/voyage-travel.aspx",
        "hospitality_url": "https://www.international.gc.ca/transparence/hospitalite-hospitality.aspx",
    },
    {
        "slug": "defence",
        "name": "National Defence",
        "travel_url": "https://www.canada.ca/en/department-national-defence/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/department-national-defence/corporate/transparency/travel-hospitality.html",
    },
    {
        "slug": "health",
        "name": "Health Canada",
        "travel_url": "https://www.canada.ca/en/health-canada/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/health-canada/corporate/transparency/travel-hospitality.html",
    },
    {
        "slug": "justice",
        "name": "Department of Justice",
        "travel_url": "https://www.canada.ca/en/department-justice/news/proactive-disclosure/travel.html",
        "hospitality_url": "https://www.canada.ca/en/department-justice/news/proactive-disclosure/hospitality.html",
    },
    {
        "slug": "innovation",
        "name": "Innovation, Science and Economic Development",
        "travel_url": "https://www.canada.ca/en/innovation-science-economic-development/news/proactive-disclosure/travel.html",
        "hospitality_url": "https://www.canada.ca/en/innovation-science-economic-development/news/proactive-disclosure/hospitality.html",
    },
    {
        "slug": "environment",
        "name": "Environment and Climate Change Canada",
        "travel_url": "https://www.canada.ca/en/environment-climate-change/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/environment-climate-change/corporate/transparency/travel-hospitality.html",
    },
    {
        "slug": "transport",
        "name": "Transport Canada",
        "travel_url": "https://www.canada.ca/en/transport-canada/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/transport-canada/corporate/transparency/travel-hospitality.html",
    },
    {
        "slug": "naturalresources",
        "name": "Natural Resources Canada",
        "travel_url": "https://www.canada.ca/en/natural-resources-canada/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/natural-resources-canada/corporate/transparency/travel-hospitality.html",
    },
    {
        "slug": "privy-council",
        "name": "Privy Council Office",
        "travel_url": "https://www.canada.ca/en/privy-council/corporate/transparency/travel-hospitality.html",
        "hospitality_url": "https://www.canada.ca/en/privy-council/corporate/transparency/travel-hospitality.html",
    },
]

# ──────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────


class _JSONFormatter(logging.Formatter):
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
            "pipeline": getattr(record, "pipeline", PIPELINE_NAME),
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

# ──────────────────────────────────────────────
# Data model
# ──────────────────────────────────────────────


@dataclass
class MinisterialExpenseRecord:
    record_id: str
    minister_name: str
    department: str
    event_purpose: str
    destination: str
    start_date: str        # ISO-8601 date
    end_date: Optional[str]
    travel_cost: float
    hospitality_cost: float
    total_cost: float
    fiscal_year: str       # e.g. "2024-2025"
    quarter: int           # 1–4
    source_url: str


@dataclass
class ExpensesSnapshot:
    version: int = 1
    last_updated: str = field(default_factory=lambda: date.today().isoformat())
    records: list[MinisterialExpenseRecord] = field(default_factory=list)


# ──────────────────────────────────────────────
# Fiscal quarter helpers
# ──────────────────────────────────────────────


def fiscal_year_for_date(d: date) -> str:
    """Return the Government of Canada fiscal year label for a given date.

    The federal fiscal year runs April 1 – March 31.
    """
    if d.month >= 4:
        return f"{d.year}-{d.year + 1}"
    return f"{d.year - 1}-{d.year}"


def fiscal_quarter_for_date(d: date) -> int:
    """Return fiscal quarter (1–4) for a given date.

    Q1: Apr–Jun, Q2: Jul–Sep, Q3: Oct–Dec, Q4: Jan–Mar.
    """
    fiscal_month = (d.month - 4) % 12
    return fiscal_month // 3 + 1


def recent_quarters(n: int = 4) -> list[tuple[str, int]]:
    """Return the n most recent completed (fiscal year, quarter) pairs."""
    today = date.today()
    quarters: list[tuple[str, int]] = []
    # Walk backward month-by-month until we have n distinct quarters.
    d = date(today.year, today.month, 1)
    seen: set[tuple[str, int]] = set()
    while len(quarters) < n:
        d = date(d.year if d.month > 1 else d.year - 1, (d.month - 2) % 12 + 1, 1)
        fy = fiscal_year_for_date(d)
        fq = fiscal_quarter_for_date(d)
        key = (fy, fq)
        if key not in seen:
            seen.add(key)
            quarters.append(key)
    return quarters


# ──────────────────────────────────────────────
# Network helpers
# ──────────────────────────────────────────────


def _fetch(url: str, timeout: int = 30) -> bytes:
    request = Request(url, headers={"User-Agent": "epac-ingest/1.0"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def _fetch_text(url: str, timeout: int = 30) -> str:
    return _fetch(url, timeout).decode("utf-8", errors="replace")


# ──────────────────────────────────────────────
# CSV link extraction
# ──────────────────────────────────────────────

_CSV_LINK_RE = re.compile(r'href=["\']([^"\']+\.csv[^"\']*)["\']', re.IGNORECASE)
_QUARTER_RE = re.compile(r"(?:q|quarter|quarter-)([1-4])", re.IGNORECASE)
_FISCAL_YEAR_RE = re.compile(r"(\d{4})[-–](\d{2,4})")


def _extract_csv_links(html: str, base_url: str) -> list[str]:
    """Extract all CSV href values from an HTML page."""
    from urllib.parse import urljoin
    return [urljoin(base_url, m.group(1)) for m in _CSV_LINK_RE.finditer(html)]


# ──────────────────────────────────────────────
# CSV normaliser
# ──────────────────────────────────────────────

# Column name variants across departments.
_MINISTER_ALIASES = {"minister", "minister's name", "name", "minister name", "nom du ministre"}
_PURPOSE_ALIASES = {"purpose", "purpose of travel", "purpose of hospitality", "raison du voyage", "objet"}
_DESTINATION_ALIASES = {"destination", "city/country", "ville/pays", "place", "lieu"}
_START_ALIASES = {"start date", "departure date", "date of travel", "date de départ", "date début"}
_END_ALIASES = {"end date", "return date", "date de retour", "date fin"}
_TRAVEL_COST_ALIASES = {"total", "transportation", "transport", "coût de transport", "travel cost", "amount"}
_HOSPITALITY_COST_ALIASES = {"total cost", "hospitality amount", "coût d'hospitalité", "amount"}


def _find_col(header: list[str], aliases: set[str]) -> Optional[int]:
    for i, col in enumerate(header):
        if col.strip().lower() in aliases:
            return i
    return None


def _parse_money(value: str) -> float:
    cleaned = re.sub(r"[^\d.]", "", value.strip())
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


_DATE_FORMATS = ["%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%B %d, %Y", "%d-%b-%Y", "%Y/%m/%d"]


def _parse_date(value: str) -> Optional[date]:
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(value.strip(), fmt).date()
        except ValueError:
            continue
    return None


def _generate_record_id(
    department_slug: str, minister_name: str, start_date: str, purpose: str
) -> str:
    raw = f"{department_slug}|{minister_name.lower()}|{start_date}|{purpose[:40].lower()}"
    return hashlib.sha1(raw.encode()).hexdigest()[:16]


def normalise_travel_csv(
    csv_bytes: bytes,
    department: dict[str, str],
    source_url: str,
    target_quarters: set[tuple[str, int]],
) -> Iterator[MinisterialExpenseRecord]:
    """Parse a travel disclosure CSV and yield normalised records for target quarters."""
    text = csv_bytes.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))
    header: Optional[list[str]] = None

    for row in reader:
        if not any(cell.strip() for cell in row):
            continue
        if header is None:
            header = row
            continue

        if len(row) < 3:
            continue

        minister_col = _find_col(header, _MINISTER_ALIASES)
        purpose_col = _find_col(header, _PURPOSE_ALIASES)
        dest_col = _find_col(header, _DESTINATION_ALIASES)
        start_col = _find_col(header, _START_ALIASES)
        end_col = _find_col(header, _END_ALIASES)
        cost_col = _find_col(header, _TRAVEL_COST_ALIASES)

        if any(c is None for c in [minister_col, start_col]):
            logger.warning(
                "travel CSV header missing required columns",
                extra={"department": department["slug"], "header": header},
            )
            return

        def get(col: Optional[int]) -> str:
            if col is None or col >= len(row):
                return ""
            return row[col].strip()

        start_str = get(start_col)
        start_d = _parse_date(start_str)
        if start_d is None:
            continue

        fy = fiscal_year_for_date(start_d)
        fq = fiscal_quarter_for_date(start_d)
        if (fy, fq) not in target_quarters:
            continue

        minister_name = get(minister_col)
        if not minister_name:
            continue

        end_str = get(end_col)
        end_d = _parse_date(end_str)
        travel_cost = _parse_money(get(cost_col) if cost_col is not None else "0")
        purpose = get(purpose_col) or "Travel"
        destination = get(dest_col) or "Canada"

        record_id = _generate_record_id(department["slug"], minister_name, start_d.isoformat(), purpose)

        yield MinisterialExpenseRecord(
            record_id=record_id,
            minister_name=minister_name,
            department=department["name"],
            event_purpose=purpose,
            destination=destination,
            start_date=start_d.isoformat(),
            end_date=end_d.isoformat() if end_d else None,
            travel_cost=round(travel_cost, 2),
            hospitality_cost=0.0,
            total_cost=round(travel_cost, 2),
            fiscal_year=fy,
            quarter=fq,
            source_url=source_url,
        )


def normalise_hospitality_csv(
    csv_bytes: bytes,
    department: dict[str, str],
    source_url: str,
    target_quarters: set[tuple[str, int]],
) -> Iterator[MinisterialExpenseRecord]:
    """Parse a hospitality disclosure CSV and yield normalised records for target quarters."""
    text = csv_bytes.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))
    header: Optional[list[str]] = None

    for row in reader:
        if not any(cell.strip() for cell in row):
            continue
        if header is None:
            header = row
            continue

        if len(row) < 3:
            continue

        minister_col = _find_col(header, _MINISTER_ALIASES)
        purpose_col = _find_col(header, _PURPOSE_ALIASES)
        dest_col = _find_col(header, _DESTINATION_ALIASES)
        start_col = _find_col(header, _START_ALIASES)
        cost_col = _find_col(header, _HOSPITALITY_COST_ALIASES)

        if any(c is None for c in [minister_col, start_col]):
            logger.warning(
                "hospitality CSV header missing required columns",
                extra={"department": department["slug"], "header": header},
            )
            return

        def get(col: Optional[int]) -> str:
            if col is None or col >= len(row):
                return ""
            return row[col].strip()

        start_str = get(start_col)
        start_d = _parse_date(start_str)
        if start_d is None:
            continue

        fy = fiscal_year_for_date(start_d)
        fq = fiscal_quarter_for_date(start_d)
        if (fy, fq) not in target_quarters:
            continue

        minister_name = get(minister_col)
        if not minister_name:
            continue

        hospitality_cost = _parse_money(get(cost_col) if cost_col is not None else "0")
        purpose = get(purpose_col) or "Hospitality"
        location = get(dest_col) or "Canada"

        record_id = _generate_record_id(
            department["slug"] + "-hosp", minister_name, start_d.isoformat(), purpose
        )

        yield MinisterialExpenseRecord(
            record_id=record_id,
            minister_name=minister_name,
            department=department["name"],
            event_purpose=purpose,
            destination=location,
            start_date=start_d.isoformat(),
            end_date=None,
            travel_cost=0.0,
            hospitality_cost=round(hospitality_cost, 2),
            total_cost=round(hospitality_cost, 2),
            fiscal_year=fy,
            quarter=fq,
            source_url=source_url,
        )


# ──────────────────────────────────────────────
# Per-department ingestion
# ──────────────────────────────────────────────


def ingest_department(
    department: dict[str, str],
    target_quarters: set[tuple[str, int]],
) -> list[MinisterialExpenseRecord]:
    """Fetch travel and hospitality CSVs for one department and return normalised records."""
    records: list[MinisterialExpenseRecord] = []

    for kind, url_key in [("travel", "travel_url"), ("hospitality", "hospitality_url")]:
        page_url = department.get(url_key, "")
        if not page_url:
            continue

        try:
            html = _fetch_text(page_url)
        except (HTTPError, URLError) as err:
            logger.warning(
                "failed to fetch department page",
                extra={"department": department["slug"], "kind": kind, "error": str(err)},
            )
            continue

        csv_links = _extract_csv_links(html, page_url)
        if not csv_links:
            logger.info(
                "no CSV links found on department page",
                extra={"department": department["slug"], "kind": kind, "url": page_url},
            )
            continue

        for csv_url in csv_links:
            try:
                csv_bytes = _fetch(csv_url)
            except (HTTPError, URLError) as err:
                logger.warning(
                    "failed to fetch CSV",
                    extra={"department": department["slug"], "url": csv_url, "error": str(err)},
                )
                continue

            normaliser = normalise_travel_csv if kind == "travel" else normalise_hospitality_csv
            for record in normaliser(csv_bytes, department, csv_url, target_quarters):
                records.append(record)

    logger.info(
        "department ingested",
        extra={"department": department["slug"], "records": len(records)},
    )
    return records


# ──────────────────────────────────────────────
# Snapshot serialisation
# ──────────────────────────────────────────────


def snapshot_to_json(snapshot: ExpensesSnapshot) -> str:
    payload = {
        "version": snapshot.version,
        "lastUpdated": snapshot.last_updated,
        "records": [
            {
                "recordID": r.record_id,
                "ministerName": r.minister_name,
                "department": r.department,
                "eventPurpose": r.event_purpose,
                "destination": r.destination,
                "startDate": r.start_date,
                **({"endDate": r.end_date} if r.end_date else {"endDate": None}),
                "travelCost": r.travel_cost,
                "hospitalityCost": r.hospitality_cost,
                "totalCost": r.total_cost,
                "fiscalYear": r.fiscal_year,
                "quarter": r.quarter,
                "sourceURL": r.source_url,
            }
            for r in snapshot.records
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False) + "\n"


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="ios/epac/ministerial-expenses.json",
        help="Path to write the JSON snapshot (default: ios/epac/ministerial-expenses.json)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the snapshot to stdout instead of writing it",
    )
    parser.add_argument(
        "--quarters",
        type=int,
        default=4,
        help="Number of most recent fiscal quarters to ingest (default: 4)",
    )
    args = parser.parse_args(argv)
    started_at = time.monotonic()

    target_quarters = set(recent_quarters(args.quarters))
    logger.info(
        "pipeline started",
        extra={
            "dry_run": args.dry_run,
            "output": args.output,
            "target_quarters": [f"{fy} Q{q}" for fy, q in sorted(target_quarters)],
        },
    )

    all_records: list[MinisterialExpenseRecord] = []
    for dept in DEPARTMENT_REGISTRY:
        dept_records = ingest_department(dept, target_quarters)
        all_records.extend(dept_records)

    # Deduplicate by record_id, keeping the last-seen value.
    seen: dict[str, MinisterialExpenseRecord] = {}
    for r in all_records:
        seen[r.record_id] = r
    unique_records = list(seen.values())
    unique_records.sort(key=lambda r: (r.minister_name, r.start_date))

    snapshot = ExpensesSnapshot(records=unique_records)
    payload = snapshot_to_json(snapshot)

    if args.dry_run:
        sys.stdout.write(payload)
    else:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(payload)

    duration_ms = int((time.monotonic() - started_at) * 1000)
    logger.info(
        "pipeline finished",
        extra={
            "records_processed": len(unique_records),
            "departments": len(DEPARTMENT_REGISTRY),
            "duration_ms": duration_ms,
            "output": "stdout" if args.dry_run else args.output,
        },
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
