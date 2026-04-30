#!/usr/bin/env python3
"""Build student financial assistance statistics for the iOS bundle."""

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
TUITION_TABLE_ID = "37100120"
TUITION_TABLE_URL = "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=3710012001"
CSFA_STATISTICAL_REVIEW_URL = "https://www.canada.ca/en/employment-social-development/programs/canada-student-loans-grants/reports/student-financial-assistance-statistics-2023-2024.html"
CSFA_ANNUAL_REPORT_URL = "https://www.canada.ca/en/employment-social-development/programs/canada-student-loans-grants/reports/csfa-annual-2023-2024.html"

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

CSFA_PARTICIPATING_CODES = {"NL", "PE", "NS", "NB", "ON", "MB", "SK", "AB", "BC", "YT"}
CSFA_YEARS = ["2021 to 2022", "2022 to 2023", "2023 to 2024"]

# ESDC CSFA Annual Report 2023-2024, Table 2A.
CSFA_LOAN_RECIPIENTS = {
    "NL": [6724, 7142, 7875],
    "PE": [2146, 2106, 2469],
    "NS": [17681, 17694, 18781],
    "NB": [11693, 11449, 12468],
    "ON": [315877, 310924, 377860],
    "MB": [14081, 15913, 19884],
    "SK": [17967, 17615, 19248],
    "AB": [113776, 125030, 123832],
    "BC": [58207, 57763, 66720],
    "YT": [204, 212, 256],
}

# ESDC CSFA Annual Report 2023-2024, Table 2B, in millions of dollars.
CSFA_LOAN_DISBURSEMENTS_MILLIONS = {
    "NL": [40.6, 44.0, 70.4],
    "PE": [11.5, 11.6, 18.5],
    "NS": [122.0, 123.7, 185.5],
    "NB": [60.6, 63.0, 87.1],
    "ON": [1503.9, 1530.5, 2567.8],
    "MB": [66.1, 75.6, 134.9],
    "SK": [108.5, 108.2, 161.0],
    "AB": [686.4, 842.6, 1083.1],
    "BC": [339.2, 336.9, 527.8],
    "YT": [1.3, 1.4, 2.5],
}

# CSFA Statistical Review 2023-2024, Table 1.3.1A, All Stages - Total.
CSFA_NATIONAL_RAP_RECIPIENTS = {
    "2021 to 2022": 285031,
    "2022 to 2023": 282716,
    "2023 to 2024": 288368,
}

# CSFA Annual Report 2023-2024, Figure 2 text version, All Stages.
CSFA_LATEST_RAP_RECIPIENTS = {
    "NL": 3985,
    "PE": 1374,
    "NS": 13285,
    "NB": 10669,
    "ON": 160576,
    "MB": 4955,
    "SK": 8621,
    "AB": 52933,
    "BC": 31916,
    "YT": 54,
}


@dataclass(frozen=True)
class TuitionYear:
    academic_year: str
    average_undergraduate_tuition: int
    year_over_year_change_percent: float | None


@dataclass(frozen=True)
class CSFAYear:
    academic_year: str
    loan_recipients: int
    loan_disbursements_millions: float
    average_loan_amount: int
    rap_recipients: int | None


@dataclass(frozen=True)
class StudentFinanceProvinceStatistics:
    province: str
    province_code: str
    csfa_participating: bool
    tuition_years: list[TuitionYear]
    csfa_years: list[CSFAYear]


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "student-finance-statistics",
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
    logger = logging.getLogger("student-finance-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def fetch_table(table_id: str) -> list[dict[str, str]]:
    url = f"{STATCAN_TABLE_BASE_URL}/{table_id}-eng.zip"
    request = Request(url, headers={"Accept": "application/zip", "User-Agent": "epac-student-finance-statistics"})
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


def build_statistics(tuition_rows: list[dict[str, str]], tuition_year_count: int = 5) -> dict[str, object]:
    tuition_by_province = _tuition_by_province_year(tuition_rows)
    province_stats: list[StudentFinanceProvinceStatistics] = []
    for province, code in PROVINCES.items():
        tuition_years = _build_tuition_years(tuition_by_province.get(province, {}), tuition_year_count)
        csfa_years = _build_csfa_years(code)
        if not tuition_years and not csfa_years:
            continue
        province_stats.append(
            StudentFinanceProvinceStatistics(
                province=province,
                province_code=code,
                csfa_participating=code in CSFA_PARTICIPATING_CODES,
                tuition_years=tuition_years,
                csfa_years=csfa_years,
            )
        )

    if not province_stats:
        raise ValueError("no student finance statistics could be composed")

    latest_tuition_year = max(year.academic_year for item in province_stats for year in item.tuition_years)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "reference_academic_year": CSFA_YEARS[-1],
        "tuition_reference_year": latest_tuition_year,
        "source": {
            "title": "ESDC CSFA Program and Statistics Canada tuition data",
            "url": CSFA_STATISTICAL_REVIEW_URL,
            "note": "CSFAP reports federal loans and RAP for participating provinces and Yukon. Quebec, Nunavut and Northwest Territories receive alternative payments instead of participating directly.",
        },
        "sources": [
            {
                "title": "ESDC — Canada Student Financial Assistance Program Statistical Review 2023-2024",
                "url": CSFA_STATISTICAL_REVIEW_URL,
                "note": "Historical CSFA and national RAP tables for academic years through 2023 to 2024.",
            },
            {
                "title": "ESDC — Canada Student Financial Assistance Program Annual Report 2023-2024",
                "url": CSFA_ANNUAL_REPORT_URL,
                "note": "Province-level loan recipients, loan disbursements, and latest RAP recipients.",
            },
            {
                "title": "Statistics Canada — Undergraduate tuition fees, Canadian students",
                "url": TUITION_TABLE_URL,
                "note": "Table 37-10-0120-01, current dollars, total field of study.",
            },
        ],
        "national_rap_recipients": [
            {"academic_year": year, "rap_recipients": recipients}
            for year, recipients in CSFA_NATIONAL_RAP_RECIPIENTS.items()
        ],
        "provinces": [asdict(item) for item in sorted(province_stats, key=lambda item: item.province_code)],
    }


def _tuition_by_province_year(rows: list[dict[str, str]]) -> dict[str, dict[str, int]]:
    result: dict[str, dict[str, int]] = {}
    for row in rows:
        province = row.get("GEO")
        if province not in PROVINCES:
            continue
        if row.get("Field of study") != "Total, field of study":
            continue
        if row.get("UOM") != "Current dollars":
            continue
        value = _optional_int_value(row)
        if value is None:
            continue
        result.setdefault(province, {})[row["REF_DATE"]] = value
    return result


def _build_tuition_years(values: dict[str, int], count: int) -> list[TuitionYear]:
    years = sorted(values)[-count:]
    result: list[TuitionYear] = []
    for year in years:
        previous_year = _previous_academic_year(year)
        previous_value = values.get(previous_year)
        change = None
        if previous_value:
            change = round(((values[year] - previous_value) / previous_value) * 100, 1)
        result.append(
            TuitionYear(
                academic_year=year,
                average_undergraduate_tuition=values[year],
                year_over_year_change_percent=change,
            )
        )
    return result


def _build_csfa_years(code: str) -> list[CSFAYear]:
    recipients = CSFA_LOAN_RECIPIENTS.get(code)
    disbursements = CSFA_LOAN_DISBURSEMENTS_MILLIONS.get(code)
    if recipients is None or disbursements is None:
        return []
    result: list[CSFAYear] = []
    for index, year in enumerate(CSFA_YEARS):
        loan_recipients = recipients[index]
        loan_disbursements = disbursements[index]
        result.append(
            CSFAYear(
                academic_year=year,
                loan_recipients=loan_recipients,
                loan_disbursements_millions=loan_disbursements,
                average_loan_amount=round((loan_disbursements * 1_000_000) / loan_recipients),
                rap_recipients=CSFA_LATEST_RAP_RECIPIENTS.get(code) if year == CSFA_YEARS[-1] else None,
            )
        )
    return result


def _optional_int_value(row: dict[str, str]) -> int | None:
    value = row.get("VALUE", "")
    if not value:
        return None
    return int(float(value))


def _previous_academic_year(ref_date: str) -> str:
    start, end = ref_date.split("/")
    return f"{int(start) - 1}/{int(end) - 1}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="../../ios/epac/student-finance-statistics.json")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    logger.info("pipeline started", extra={"dry_run": args.dry_run, "output": args.output})

    try:
        tuition_rows = fetch_table(TUITION_TABLE_ID)
        snapshot = build_statistics(tuition_rows)
    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.error("fetch or build failed", extra={"error": f"{type(exc).__name__}: {exc}", "duration_ms": duration_ms})
        raise

    payload = json.dumps(snapshot, indent=2, sort_keys=True) + "\n"
    if args.dry_run:
        print(payload, end="")
    else:
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(payload)

    duration_ms = int((time.monotonic() - start) * 1000)
    logger.info("pipeline finished", extra={"records_processed": len(snapshot["provinces"]), "duration_ms": duration_ms})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
