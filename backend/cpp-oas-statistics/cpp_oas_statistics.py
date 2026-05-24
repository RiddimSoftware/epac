#!/usr/bin/env python3
"""Fetch CPP retirement and OAS pension statistics by province.

Recipient counts come from two ESDC datasets published on open.canada.ca:

- CPP recipients by Place of Residence
  (dataset 1fab2afd-4f3c-4922-a07e-58d7bed9dcfc)
- OAS recipients by Province
  (dataset 77381606-95c0-411a-a7cd-eba5d038c1c4)

Average benefit amounts by province are not published; only national averages
exist (see Annual Statistics Tables, dataset f064a144-...). This pipeline
emits provincial recipient counts for the last three matching periods and
defers benefit averages to the consumer (which can show the published
national figure as context).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import argparse
import csv
import io
import json
import logging
from pathlib import Path
import ssl
import sys
import time
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from statistics_artifacts import PublishedArtifact, publish_statistics_payload


CPP_CSV_URL = (
    "https://open.canada.ca/data/dataset/1fab2afd-4f3c-4922-a07e-58d7bed9dcfc/"
    "resource/5ddf2bac-666e-4342-81c8-59274da78425/download/"
    "20260430-cpres-cppben.csv"
)
OAS_CSV_URL = (
    "https://open.canada.ca/data/dataset/77381606-95c0-411a-a7cd-eba5d038c1c4/"
    "resource/ae931981-b9ac-4b5c-9b6b-2c70c1fe448f/download/"
    "20250331-svpres-oasben.csv"
)
CPP_DATASET_URL = "https://open.canada.ca/data/en/dataset/1fab2afd-4f3c-4922-a07e-58d7bed9dcfc"
OAS_DATASET_URL = "https://open.canada.ca/data/en/dataset/77381606-95c0-411a-a7cd-eba5d038c1c4"
ESDC_BULLETIN_URL = (
    "https://www.canada.ca/en/employment-social-development/programs/"
    "pensions/reports/statistical-bulletin.html"
)

PIPELINE_NAME = "cpp-oas-statistics"

# CSV column headers (English row) for each input.
CPP_PERIOD_COL = "Period"
CPP_PROVINCE_COL = "Province"
CPP_RETIREMENT_COL = "Retirement"
OAS_PERIOD_COL = "Period"
OAS_PROVINCE_COL = "Province"
OAS_PENSION_COL = "Old Age Security Pension"

# Province name (as written in source CSVs) → ISO 3166-2:CA two-letter code.
PROVINCE_CODES: dict[str, str] = {
    "NFLD.&LAB./T-N.&LAB.": "NL",
    "P.E.I./Î.-P.-É.": "PE",
    "N.S./N.-É.": "NS",
    "N.B./N.-B.": "NB",
    "QUE./QUÉ.": "QC",
    "ONTARIO": "ON",
    "MANITOBA": "MB",
    "SASKATCHEWAN": "SK",
    "ALBERTA": "AB",
    "B.C./C.-B.": "BC",
    "YUKON": "YT",
    "N.W.T./T.N.-O.": "NT",
    "NUNAVUT": "NU",
}

PROVINCE_DISPLAY_NAMES: dict[str, str] = {
    "NL": "Newfoundland and Labrador",
    "PE": "Prince Edward Island",
    "NS": "Nova Scotia",
    "NB": "New Brunswick",
    "QC": "Quebec",
    "ON": "Ontario",
    "MB": "Manitoba",
    "SK": "Saskatchewan",
    "AB": "Alberta",
    "BC": "British Columbia",
    "YT": "Yukon",
    "NT": "Northwest Territories",
    "NU": "Nunavut",
}

MONTH_ABBREVS: dict[str, int] = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7,
    "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
}


@dataclass(frozen=True)
class YearlyDatum:
    year: int
    cpp_retirement_recipients: int | None
    oas_pension_recipients: int | None


@dataclass(frozen=True)
class ProvinceStatistic:
    province: str
    province_code: str
    cpp_retirement_recipients: int | None
    cpp_reference_period: str | None
    oas_pension_recipients: int | None
    oas_reference_period: str | None
    history: list[YearlyDatum]


@dataclass(frozen=True)
class NationalSnapshot:
    cpp_retirement_recipients: int
    cpp_reference_period: str
    oas_pension_recipients: int
    oas_reference_period: str


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "cpp-oas-statistics",
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in {
                "name", "msg", "args", "levelname", "levelno", "pathname",
                "filename", "module", "exc_info", "exc_text", "stack_info",
                "lineno", "funcName", "created", "msecs", "relativeCreated",
                "thread", "threadName", "taskName", "processName", "process",
                "message",
            }:
                payload[key] = value
        return json.dumps(payload, sort_keys=True)


def configure_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JSONFormatter())
    logger = logging.getLogger("cpp-oas-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def _ssl_context() -> ssl.SSLContext:
    for cafile in ("/etc/ssl/cert.pem", "/opt/homebrew/etc/ca-certificates/cert.pem"):
        try:
            return ssl.create_default_context(cafile=cafile)
        except FileNotFoundError:
            continue
    return ssl.create_default_context()


def fetch_csv(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "epac-cpp-oas-statistics"})
    with urlopen(request, timeout=30, context=_ssl_context()) as response:
        return response.read()


def parse_period(value: str) -> tuple[int, int] | None:
    """Parse "Jan. / jan. 2012" → (2012, 1). Return None if not parseable."""
    text = value.strip()
    if not text:
        return None
    parts = text.split()
    year: int | None = None
    month: int | None = None
    for part in parts:
        token = part.strip(".").lower()
        if token.isdigit() and len(token) == 4:
            year = int(token)
            continue
        if month is None and token in MONTH_ABBREVS:
            month = MONTH_ABBREVS[token]
    if year is None or month is None:
        return None
    return year, month


def _to_int(value: str) -> int | None:
    if value is None:
        return None
    cleaned = value.strip().replace(",", "").replace('"', "")
    if not cleaned or cleaned.upper() in {"X", "N/A", "..", ".."}:
        return None
    try:
        return int(round(float(cleaned)))
    except ValueError:
        return None


def _read_rows(csv_bytes: bytes, header_row_index: int) -> list[dict[str, str]]:
    """Decode Latin-1 CSV, skip rows above the English header, return DictReader rows."""
    text = csv_bytes.decode("latin-1")
    lines = list(csv.reader(io.StringIO(text)))
    if header_row_index >= len(lines):
        return []
    header = lines[header_row_index]
    rows: list[dict[str, str]] = []
    for line in lines[header_row_index + 1:]:
        if not any(cell.strip() for cell in line):
            continue
        if line[0].strip().lower().startswith("période"):
            continue
        row = {header[i] if i < len(header) else f"col{i}": line[i] if i < len(line) else ""
               for i in range(max(len(header), len(line)))}
        rows.append(row)
    return rows


def _normalize_province(name: str) -> str | None:
    cleaned = name.strip().replace('"', "")
    return PROVINCE_CODES.get(cleaned)


def _format_period(year: int, month: int) -> str:
    return f"{year:04d}-{month:02d}"


def _english_month_label(year: int, month: int) -> str:
    names = ["January", "February", "March", "April", "May", "June",
             "July", "August", "September", "October", "November", "December"]
    return f"{names[month - 1]} {year}"


def _build_history_for(
    cpp_by_province_year: dict[str, dict[int, tuple[int, int]]],
    oas_by_province_year: dict[str, dict[int, tuple[int, int]]],
    code: str,
    target_years: list[int],
) -> list[YearlyDatum]:
    history: list[YearlyDatum] = []
    for year in target_years:
        cpp_value = cpp_by_province_year.get(code, {}).get(year)
        oas_value = oas_by_province_year.get(code, {}).get(year)
        history.append(
            YearlyDatum(
                year=year,
                cpp_retirement_recipients=cpp_value[0] if cpp_value else None,
                oas_pension_recipients=oas_value[0] if oas_value else None,
            )
        )
    return history


def build_payload(cpp_csv_bytes: bytes, oas_csv_bytes: bytes) -> dict[str, object]:
    cpp_rows = _read_rows(cpp_csv_bytes, header_row_index=0)
    oas_rows = _read_rows(oas_csv_bytes, header_row_index=3)

    # province_code -> year -> (recipients, month) capturing the LATEST month seen for that year.
    cpp_by_province_year: dict[str, dict[int, tuple[int, int]]] = {}
    cpp_latest_period_by_province: dict[str, tuple[int, int, int]] = {}

    for row in cpp_rows:
        code = _normalize_province(row.get(CPP_PROVINCE_COL, ""))
        if code is None:
            continue
        period = parse_period(row.get(CPP_PERIOD_COL, ""))
        if period is None:
            continue
        year, month = period
        recipients = _to_int(row.get(CPP_RETIREMENT_COL, ""))
        if recipients is None:
            continue
        existing = cpp_by_province_year.setdefault(code, {}).get(year)
        if existing is None or month > existing[1]:
            cpp_by_province_year[code][year] = (recipients, month)
        latest = cpp_latest_period_by_province.get(code)
        if latest is None or (year, month) > (latest[0], latest[1]):
            cpp_latest_period_by_province[code] = (year, month, recipients)

    oas_by_province_year: dict[str, dict[int, tuple[int, int]]] = {}
    oas_latest_period_by_province: dict[str, tuple[int, int, int]] = {}

    for row in oas_rows:
        code = _normalize_province(row.get(OAS_PROVINCE_COL, ""))
        if code is None:
            continue
        period = parse_period(row.get(OAS_PERIOD_COL, ""))
        if period is None:
            continue
        year, month = period
        recipients = _to_int(row.get(OAS_PENSION_COL, ""))
        if recipients is None:
            continue
        existing = oas_by_province_year.setdefault(code, {}).get(year)
        if existing is None or month > existing[1]:
            oas_by_province_year[code][year] = (recipients, month)
        latest = oas_latest_period_by_province.get(code)
        if latest is None or (year, month) > (latest[0], latest[1]):
            oas_latest_period_by_province[code] = (year, month, recipients)

    # Pick the three most recent years where BOTH CPP and OAS have data nationally.
    common_years_per_province = [
        set(cpp_by_province_year.get(code, {})).intersection(oas_by_province_year.get(code, {}))
        for code in PROVINCE_CODES.values()
        if code in cpp_by_province_year and code in oas_by_province_year
    ]
    if not common_years_per_province:
        raise ValueError("no overlapping reporting years between CPP and OAS datasets")
    common_years = sorted(set.intersection(*common_years_per_province), reverse=True)
    target_years = sorted(common_years[:3])
    if not target_years:
        raise ValueError("no overlapping reporting years across all provinces")

    province_records: list[ProvinceStatistic] = []
    for code in PROVINCE_CODES.values():
        cpp_latest = cpp_latest_period_by_province.get(code)
        oas_latest = oas_latest_period_by_province.get(code)
        history = _build_history_for(
            cpp_by_province_year, oas_by_province_year, code, target_years
        )
        province_records.append(
            ProvinceStatistic(
                province=PROVINCE_DISPLAY_NAMES[code],
                province_code=code,
                cpp_retirement_recipients=cpp_latest[2] if cpp_latest else None,
                cpp_reference_period=_format_period(cpp_latest[0], cpp_latest[1]) if cpp_latest else None,
                oas_pension_recipients=oas_latest[2] if oas_latest else None,
                oas_reference_period=_format_period(oas_latest[0], oas_latest[1]) if oas_latest else None,
                history=history,
            )
        )

    cpp_national = sum(
        item.cpp_retirement_recipients or 0
        for item in province_records
    )
    oas_national = sum(
        item.oas_pension_recipients or 0
        for item in province_records
    )
    cpp_national_period = max(cpp_latest_period_by_province.values())[:2]
    oas_national_period = max(oas_latest_period_by_province.values())[:2]
    national = NationalSnapshot(
        cpp_retirement_recipients=cpp_national,
        cpp_reference_period=_format_period(*cpp_national_period),
        oas_pension_recipients=oas_national,
        oas_reference_period=_format_period(*oas_national_period),
    )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "title": "Employment and Social Development Canada — CPP/OAS Statistical Bulletin",
            "url": ESDC_BULLETIN_URL,
            "note": (
                "Provincial recipient counts come from the ESDC monthly Statistical Bulletin "
                "datasets published on open.canada.ca. Average monthly benefit amounts are "
                "only published nationally; provincial-level averages are not available."
            ),
        },
        "datasets": [
            {
                "id": "1fab2afd-4f3c-4922-a07e-58d7bed9dcfc",
                "title": "Canada Pension Plan – Beneficiaries by Place of Residence",
                "url": CPP_DATASET_URL,
                "csv": CPP_CSV_URL,
            },
            {
                "id": "77381606-95c0-411a-a7cd-eba5d038c1c4",
                "title": "Old Age Security – Beneficiaries by Province",
                "url": OAS_DATASET_URL,
                "csv": OAS_CSV_URL,
            },
        ],
        "history_years": target_years,
        "provinces": [asdict(item) for item in province_records],
        "national": asdict(national),
    }


def publish_payload(
    payload: object,
    *,
    bucket: str | None = None,
    s3_client: object | None = None,
) -> list[PublishedArtifact]:
    return publish_statistics_payload(
        PIPELINE_NAME,
        payload,
        bucket=bucket,
        s3_client=s3_client,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fetch province-level CPP/OAS statistics")
    parser.add_argument("--output", help="Write JSON to a file instead of stdout")
    parser.add_argument("--s3-publish", action="store_true", help="Publish JSON artifacts to S3")
    parser.add_argument("--s3-bucket", help="S3 bucket for --s3-publish; defaults to ARTIFACTS_BUCKET")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    output_target = "s3" if args.s3_publish else args.output or "stdout"
    logger.info("pipeline started", extra={"output": output_target})
    try:
        cpp_bytes = fetch_csv(CPP_CSV_URL)
        oas_bytes = fetch_csv(OAS_CSV_URL)
        payload = build_payload(cpp_bytes, oas_bytes)
    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.error(
            "fetch failed from open.canada.ca",
            extra={
                "error": f"{type(exc).__name__}: {exc}",
                "url": f"{CPP_CSV_URL} | {OAS_CSV_URL}",
                "duration_ms": duration_ms,
            },
        )
        raise

    body = json.dumps(payload, indent=2, sort_keys=True)
    if args.s3_publish:
        published = publish_payload(payload, bucket=args.s3_bucket)
    elif args.output:
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(body)
            output.write("\n")
        published = []
    else:
        sys.stdout.write(body)
        sys.stdout.write("\n")
        published = []

    duration_ms = int((time.monotonic() - start) * 1000)
    logger.info(
        "pipeline finished",
        extra={
            "records_processed": len(payload["provinces"]),
            "history_years": payload["history_years"],
            "s3_objects": [artifact.key for artifact in published],
            "duration_ms": duration_ms,
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
