#!/usr/bin/env python3
"""Fetch Consumer Price Index statistics from Statistics Canada."""

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
STATCAN_CPI_TABLE_URL = "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1810000401"

CPI_TABLE_ID = "18100004"
NATIONAL_GEO = "Canada"

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
}

CATEGORIES = {
    "all_items": "All-items",
    "food": "Food",
    "shelter": "Shelter",
    "energy": "Energy",
}


@dataclass(frozen=True)
class CPIMonth:
    ref_date: str
    all_items_index: float
    all_items_yoy_percent: float
    food_yoy_percent: float
    shelter_yoy_percent: float
    energy_yoy_percent: float


@dataclass(frozen=True)
class CPIProvinceStatistics:
    province: str
    province_code: str
    reference_month: str
    all_items_index: float
    all_items_yoy_percent: float
    food_yoy_percent: float
    shelter_yoy_percent: float
    energy_yoy_percent: float
    national_all_items_yoy_percent: float
    months: list[CPIMonth]


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "cpi-statistics",
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
    logger = logging.getLogger("cpi-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def fetch_table(table_id: str) -> list[dict[str, str]]:
    url = f"{STATCAN_TABLE_BASE_URL}/{table_id}-eng.zip"
    request = Request(url, headers={"Accept": "application/zip", "User-Agent": "epac-cpi-statistics"})
    with urlopen(request, timeout=45, context=_ssl_context()) as response:
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


def build_statistics(rows: list[dict[str, str]], months: int = 24) -> dict[str, object]:
    values = _values_by_geo_category_month(rows)
    national = _build_geo_statistics(NATIONAL_GEO, "CA", values, months)
    if national is None:
        raise ValueError("no national CPI statistics could be composed")

    province_stats: list[CPIProvinceStatistics] = []
    for province, code in PROVINCES.items():
        statistic = _build_geo_statistics(province, code, values, months, national)
        if statistic is not None:
            province_stats.append(statistic)

    if not province_stats:
        raise ValueError("no province CPI statistics could be composed")

    latest_reference_month = max(item.reference_month for item in province_stats)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "title": "Statistics Canada — Consumer Price Index",
            "url": STATCAN_CPI_TABLE_URL,
            "note": "Monthly CPI table 18-10-0004-01 is not seasonally adjusted and normally published about three weeks after the reference month.",
        },
        "statcan_tables": [
            {
                "id": "18-10-0004-01",
                "title": "Consumer Price Index, monthly, not seasonally adjusted",
                "url": STATCAN_CPI_TABLE_URL,
            },
        ],
        "reference_month": latest_reference_month,
        "national": asdict(national),
        "provinces": [asdict(item) for item in sorted(province_stats, key=lambda item: item.province_code)],
    }


def _values_by_geo_category_month(rows: list[dict[str, str]]) -> dict[str, dict[str, dict[str, float]]]:
    result: dict[str, dict[str, dict[str, float]]] = {}
    geographies = set(PROVINCES) | {NATIONAL_GEO}
    category_by_label = {label: key for key, label in CATEGORIES.items()}

    for row in rows:
        geography = row.get("GEO")
        if geography not in geographies:
            continue
        category = category_by_label.get(row.get("Products and product groups", ""))
        if category is None:
            continue
        value = _optional_float_value(row)
        if value is None:
            continue
        result.setdefault(geography, {}).setdefault(category, {})[row["REF_DATE"]] = value
    return result


def _build_geo_statistics(
    geography: str,
    code: str,
    values: dict[str, dict[str, dict[str, float]]],
    months: int,
    national: CPIProvinceStatistics | None = None,
) -> CPIProvinceStatistics | None:
    category_values = values.get(geography, {})
    common_months = sorted(set.intersection(*(set(category_values.get(category, {})) for category in CATEGORIES)))
    trend_months = [
        month for month in common_months
        if all(_previous_year(month) in category_values[category] for category in CATEGORIES)
    ]
    if not trend_months:
        return None

    latest_month = trend_months[-1]
    recent_months = [
        CPIMonth(
            ref_date=month,
            all_items_index=round(category_values["all_items"][month], 1),
            all_items_yoy_percent=_year_over_year(category_values["all_items"], month),
            food_yoy_percent=_year_over_year(category_values["food"], month),
            shelter_yoy_percent=_year_over_year(category_values["shelter"], month),
            energy_yoy_percent=_year_over_year(category_values["energy"], month),
        )
        for month in trend_months[-months:]
    ]

    national_yoy = national.all_items_yoy_percent if national else _year_over_year(category_values["all_items"], latest_month)
    return CPIProvinceStatistics(
        province=geography,
        province_code=code,
        reference_month=latest_month,
        all_items_index=round(category_values["all_items"][latest_month], 1),
        all_items_yoy_percent=_year_over_year(category_values["all_items"], latest_month),
        food_yoy_percent=_year_over_year(category_values["food"], latest_month),
        shelter_yoy_percent=_year_over_year(category_values["shelter"], latest_month),
        energy_yoy_percent=_year_over_year(category_values["energy"], latest_month),
        national_all_items_yoy_percent=national_yoy,
        months=recent_months,
    )


def _optional_float_value(row: dict[str, str]) -> float | None:
    value = row.get("VALUE", "")
    if not value:
        return None
    return float(value)


def _previous_year(ref_date: str) -> str:
    year, month = ref_date.split("-")
    return f"{int(year) - 1}-{month}"


def _year_over_year(values: dict[str, float], ref_date: str) -> float:
    current = values[ref_date]
    previous = values[_previous_year(ref_date)]
    return round(((current - previous) / previous) * 100, 1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fetch province-level CPI statistics")
    parser.add_argument("--output", help="Write JSON to a file instead of stdout")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    logger.info("pipeline started", extra={"output": args.output or "stdout"})
    try:
        payload = build_statistics(fetch_table(CPI_TABLE_ID))
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
