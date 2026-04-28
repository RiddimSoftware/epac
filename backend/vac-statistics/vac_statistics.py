#!/usr/bin/env python3
"""Build a Veterans Affairs Canada statistics snapshot.

VAC's current public data for this ticket is spread across HTML report pages
rather than stable CSV downloads. Keep the extracted values in one typed table
with source URLs so the bundled app data is reviewable and reproducible.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import argparse
import json
import logging
import sys
import time


FACTS_AND_FIGURES_URL = "https://www.veterans.gc.ca/en/news-and-media/facts-and-figures"
PROCESSING_SUMMARY_URL = (
    "https://www.veterans.gc.ca/en/about-vac/our-values/addressing-wait-times-veterans/"
    "disability-benefits-processing-summary-report"
)
DRR_2024_URL = (
    "https://www.veterans.gc.ca/en/about-vac/reports-policies-and-legislation/"
    "departmental-reports/departmental-results-reports/departmental-results-report-2023-2024"
)
DRR_2025_URL = (
    "https://www.veterans.gc.ca/en/about-vac/reports-policies-and-legislation/"
    "departmental-reports/departmental-results-reports/departmental-results-report-2024-2025"
)


@dataclass(frozen=True)
class AnnualStatistic:
    fiscal_year: str
    disability_pension_recipients: int | None
    pain_and_suffering_compensation_recipients: int | None
    additional_pain_and_suffering_compensation_recipients: int | None
    disability_pension_expenditures_millions: float | None
    pain_and_suffering_compensation_expenditures_millions: float | None
    additional_pain_and_suffering_compensation_expenditures_millions: float | None
    benefits_services_support_spending_dollars: int | None
    service_standard_met_percent: float | None
    first_application_average_weeks: float | None
    is_forecast: bool


@dataclass(frozen=True)
class ProvinceStatistic:
    province: str
    province_code: str
    census_veterans: int
    estimated_war_service_veterans: int | None


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "vac-statistics",
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
    logger = logging.getLogger("vac-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def build_payload() -> dict[str, object]:
    annual = [
        AnnualStatistic("2020-21", 87554, 88744, 18326, 1125.5, 1085.5, 154.1, None, 30, None, False),
        AnnualStatistic("2021-22", 80318, 99460, 21846, 1065.1, 1543.0, 180.3, 5240551120, 46, 39.7, False),
        AnnualStatistic("2022-23", 75500, 107400, 26300, 1046.6, 1506.2, 228.0, 5237608937, 55, 27.5, True),
        AnnualStatistic("2023-24", None, None, None, None, None, None, 5838792540, 69, 18.8, False),
        AnnualStatistic("2024-25", None, None, None, None, None, None, 7425077871, 47, 21.0, False),
    ]
    provinces = [
        ProvinceStatistic("Newfoundland and Labrador", "NL", 8915, 300),
        ProvinceStatistic("Prince Edward Island", "PE", 3645, 200),
        ProvinceStatistic("Nova Scotia", "NS", 33200, 1300),
        ProvinceStatistic("New Brunswick", "NB", 20305, 1000),
        ProvinceStatistic("Quebec", "QC", 104695, 2000),
        ProvinceStatistic("Ontario", "ON", 149020, 11000),
        ProvinceStatistic("Manitoba", "MB", 14725, 1100),
        ProvinceStatistic("Saskatchewan", "SK", 11435, 800),
        ProvinceStatistic("Alberta", "AB", 49880, 2000),
        ProvinceStatistic("British Columbia", "BC", 63845, 5500),
    ]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "title": "Veterans Affairs Canada - Facts and Figures / Departmental Results Reports",
            "url": FACTS_AND_FIGURES_URL,
            "note": (
                "Provincial Veteran population comes from the 2021 Census. Disability benefit "
                "recipients, processing, and spending figures are national VAC figures; provincial "
                "benefit-processing results are not published in the source tables."
            ),
        },
        "source_pages": [
            {"title": "VAC Facts and Figures", "url": FACTS_AND_FIGURES_URL},
            {"title": "Disability Benefit Processing Summary Report", "url": PROCESSING_SUMMARY_URL},
            {"title": "Departmental Results Report 2023-2024", "url": DRR_2024_URL},
            {"title": "Departmental Results Report 2024-2025", "url": DRR_2025_URL},
        ],
        "national_summary": {
            "reference_date": "2024-03-31",
            "disability_benefit_recipients": 144174,
            "disability_benefit_expenditures_dollars": 2400000000,
            "backlog_applications": 5637,
            "pending_applications": 35265,
            "first_application_average_weeks": 18.8,
            "first_application_median_weeks": 11.3,
        },
        "annual": [asdict(item) for item in annual],
        "provinces": [asdict(item) for item in provinces],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build VAC statistics snapshot")
    parser.add_argument("--output", help="Write JSON to a file instead of stdout")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    logger.info("pipeline started", extra={"output": args.output or "stdout"})
    payload = build_payload()
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
            "records_processed": len(payload["annual"]) + len(payload["provinces"]),
            "duration_ms": duration_ms,
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
