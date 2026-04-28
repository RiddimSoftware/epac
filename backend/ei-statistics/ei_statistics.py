#!/usr/bin/env python3
"""Fetch Employment Insurance statistics from Statistics Canada tables.

The monthly Employment Insurance Statistics series is produced from EI
administrative data provided by Service Canada and Employment and Social
Development Canada. This ingest composes province-level values from:

- 14-10-0011-01 regular beneficiaries
- 14-10-0005-01 claims received
- 14-10-0008-01 benefit payments and benefit weeks
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import argparse
import csv
import io
import json
import logging
import ssl
import sys
import time
from urllib.request import Request, urlopen
from zipfile import ZipFile


STATCAN_TABLE_BASE_URL = "https://www150.statcan.gc.ca/n1/tbl/csv"
ESDC_SOURCE_URL = "https://www.canada.ca/en/employment-social-development/programs/ei/statistics.html"

BENEFICIARIES_TABLE_ID = "14100011"
CLAIMS_TABLE_ID = "14100005"
BENEFITS_TABLE_ID = "14100008"

PROVINCES = {
    "Newfoundland and Labrador": "NL",
    "Prince Edward Island": "PE",
    "Nova Scotia": "NS",
    "New Brunswick": "NB",
    "Quebec": "QC",
    "Ontario": "ON",
    "Manitoba": "MB",
    "Saskatchewan": "SK",
    "Alberta": "AB",
    "British Columbia": "BC",
    "Yukon": "YT",
    "Northwest Territories": "NT",
    "Nunavut": "NU",
}


@dataclass(frozen=True)
class EIMonth:
    ref_date: str
    beneficiaries: int
    claims_received: int
    average_weekly_benefit: float


@dataclass(frozen=True)
class EIProvinceStatistics:
    province: str
    province_code: str
    reference_month: str
    beneficiaries: int
    claims_received: int
    claims_received_previous_year: int | None
    claims_year_over_year_change_percent: float | None
    average_weekly_benefit: float
    months: list[EIMonth]


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "ei-statistics",
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in {
                "name",
                "msg",
                "args",
                "levelname",
                "levelno",
                "pathname",
                "filename",
                "module",
                "exc_info",
                "exc_text",
                "stack_info",
                "lineno",
                "funcName",
                "created",
                "msecs",
                "relativeCreated",
                "thread",
                "threadName",
                "taskName",
                "processName",
                "process",
                "message",
            }:
                payload[key] = value
        return json.dumps(payload, sort_keys=True)


def configure_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JSONFormatter())
    logger = logging.getLogger("ei-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def fetch_table(table_id: str) -> list[dict[str, str]]:
    url = f"{STATCAN_TABLE_BASE_URL}/{table_id}-eng.zip"
    request = Request(url, headers={"Accept": "application/zip", "User-Agent": "epac-ei-statistics"})
    with urlopen(request, timeout=30, context=_ssl_context()) as response:
        data = response.read()
    return parse_table_zip(data, f"{table_id}.csv")


def _ssl_context() -> ssl.SSLContext:
    for cafile in ("/etc/ssl/cert.pem", "/opt/homebrew/etc/ca-certificates/cert.pem"):
        try:
            return ssl.create_default_context(cafile=cafile)
        except FileNotFoundError:
            continue
    return ssl.create_default_context()


def parse_table_zip(data: bytes, csv_name: str) -> list[dict[str, str]]:
    with ZipFile(io.BytesIO(data)) as archive:
        with archive.open(csv_name) as csv_file:
            text = io.TextIOWrapper(csv_file, encoding="utf-8-sig", newline="")
            return list(csv.DictReader(text))


def build_statistics(
    beneficiary_rows: list[dict[str, str]],
    claim_rows: list[dict[str, str]],
    benefit_rows: list[dict[str, str]],
    months: int = 12,
) -> dict[str, object]:
    beneficiaries = _beneficiaries_by_province_month(beneficiary_rows)
    claims = _claims_by_province_month(claim_rows)
    average_benefits = _average_weekly_benefit_by_province_month(benefit_rows)

    province_stats: list[EIProvinceStatistics] = []
    for province, code in PROVINCES.items():
        common_months = sorted(
            set(beneficiaries.get(province, {}))
            & set(claims.get(province, {}))
            & set(average_benefits.get(province, {}))
        )
        if not common_months:
            continue
        latest_month = common_months[-1]
        latest_claims = claims[province][latest_month]
        previous_year_month = _previous_year(latest_month)
        previous_year_claims = claims.get(province, {}).get(previous_year_month)
        change = _percent_change(latest_claims, previous_year_claims)
        recent_months = [
            EIMonth(
                ref_date=month,
                beneficiaries=beneficiaries[province][month],
                claims_received=claims[province][month],
                average_weekly_benefit=round(average_benefits[province][month], 2),
            )
            for month in common_months[-months:]
        ]
        province_stats.append(
            EIProvinceStatistics(
                province=province,
                province_code=code,
                reference_month=latest_month,
                beneficiaries=beneficiaries[province][latest_month],
                claims_received=latest_claims,
                claims_received_previous_year=previous_year_claims,
                claims_year_over_year_change_percent=change,
                average_weekly_benefit=round(average_benefits[province][latest_month], 2),
                months=recent_months,
            )
        )

    if not province_stats:
        raise ValueError("no province EI statistics could be composed")

    latest_reference_month = max(item.reference_month for item in province_stats)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "title": "Employment and Social Development Canada — EI Statistics",
            "url": ESDC_SOURCE_URL,
            "note": "Monthly Statistics Canada EI tables are produced from Service Canada and ESDC administrative data.",
        },
        "statcan_tables": [
            {
                "id": "14-10-0011-01",
                "title": "Employment insurance beneficiaries (regular benefits) by province and territory, monthly, seasonally adjusted",
                "url": "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1410001101",
            },
            {
                "id": "14-10-0005-01",
                "title": "Employment insurance claims received by province and territory, monthly, seasonally adjusted",
                "url": "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1410000501",
            },
            {
                "id": "14-10-0008-01",
                "title": "Employment insurance regular income benefit characteristics, monthly, seasonally adjusted",
                "url": "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1410000801",
            },
        ],
        "reference_month": latest_reference_month,
        "provinces": [asdict(item) for item in sorted(province_stats, key=lambda item: item.province_code)],
    }


def _beneficiaries_by_province_month(rows: list[dict[str, str]]) -> dict[str, dict[str, int]]:
    result: dict[str, dict[str, int]] = {}
    for row in rows:
        if row.get("GEO") not in PROVINCES:
            continue
        if row.get("Beneficiary detail") != "Regular benefits":
            continue
        if row.get("Sex") != "Both sexes" or row.get("Age group") != "15 years and over":
            continue
        value = _optional_int_value(row)
        if value is not None:
            _set_metric(result, row["GEO"], row["REF_DATE"], value)
    return result


def _claims_by_province_month(rows: list[dict[str, str]]) -> dict[str, dict[str, int]]:
    result: dict[str, dict[str, int]] = {}
    for row in rows:
        if row.get("GEO") not in PROVINCES:
            continue
        if row.get("Type of claim") != "Initial and renewal claims":
            continue
        if row.get("Claim detail") != "Received":
            continue
        value = _optional_int_value(row)
        if value is not None:
            _set_metric(result, row["GEO"], row["REF_DATE"], value)
    return result


def _average_weekly_benefit_by_province_month(rows: list[dict[str, str]]) -> dict[str, dict[str, float]]:
    payments: dict[str, dict[str, float]] = {}
    weeks: dict[str, dict[str, float]] = {}
    for row in rows:
        if row.get("GEO") not in PROVINCES:
            continue
        characteristic = row.get("Benefit characteristics")
        value = _optional_float_value(row)
        if value is None:
            continue
        if characteristic == "Benefit payments":
            _set_metric(payments, row["GEO"], row["REF_DATE"], value)
        elif characteristic == "Benefit weeks":
            _set_metric(weeks, row["GEO"], row["REF_DATE"], value)

    result: dict[str, dict[str, float]] = {}
    for province, payment_by_month in payments.items():
        for month, payment in payment_by_month.items():
            benefit_weeks = weeks.get(province, {}).get(month)
            if benefit_weeks:
                _set_metric(result, province, month, payment / benefit_weeks)
    return result


def _set_metric(store: dict[str, dict[str, object]], province: str, ref_date: str, value: object) -> None:
    store.setdefault(province, {})[ref_date] = value


def _optional_int_value(row: dict[str, str]) -> int | None:
    value = row.get("VALUE", "")
    if not value:
        return None
    return int(round(float(value)))


def _optional_float_value(row: dict[str, str]) -> float | None:
    value = row.get("VALUE", "")
    if not value:
        return None
    return float(value)


def _previous_year(ref_date: str) -> str:
    year, month = ref_date.split("-")
    return f"{int(year) - 1}-{month}"


def _percent_change(current: int, previous: int | None) -> float | None:
    if previous in (None, 0):
        return None
    return round(((current - previous) / previous) * 100, 1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fetch province-level EI statistics")
    parser.add_argument("--output", help="Write JSON to a file instead of stdout")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    logger.info("pipeline started", extra={"output": args.output or "stdout"})
    try:
        payload = build_statistics(
            beneficiary_rows=fetch_table(BENEFICIARIES_TABLE_ID),
            claim_rows=fetch_table(CLAIMS_TABLE_ID),
            benefit_rows=fetch_table(BENEFITS_TABLE_ID),
        )
    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.error(
            "fetch failed from Statistics Canada",
            extra={
                "error": f"{type(exc).__name__}: {exc}",
                "url": STATCAN_TABLE_BASE_URL,
                "duration_ms": duration_ms,
            },
        )
        raise

    body = json.dumps(payload, indent=2, sort_keys=True)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(body)
            output.write("\n")
    else:
        sys.stdout.write(body)
        sys.stdout.write("\n")

    duration_ms = int((time.monotonic() - start) * 1000)
    logger.info(
        "pipeline finished",
        extra={
            "records_processed": len(payload["provinces"]),
            "reference_month": payload["reference_month"],
            "duration_ms": duration_ms,
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
