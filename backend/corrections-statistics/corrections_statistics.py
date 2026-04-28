#!/usr/bin/env python3
"""Build federal corrections statistics for the iOS bundle."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import argparse
import json
import logging
import sys
import time


CSC_DRR_2023_2024_URL = "https://www.canada.ca/en/correctional-service/corporate/transparency/reporting/departmental-results-reports/2023-2024.html"
CSC_ICAF_2023_2024_URL = "https://www.canada.ca/en/correctional-service/corporate/library/offenders/indigenous/indigenous-accountability-report/accountability-report-2023-2024.html"
OCI_ANNUAL_REPORT_2024_2025_URL = "https://oci-bec.gc.ca/en/content/office-correctional-investigator-annual-report-2024-25"
STATCAN_CENSUS_PROFILE_URL = "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof/details/page.cfm?DGUIDlist=2021A000011124&GENDERlist=1&HEADERlist=30%2C19&LANG=E&STATISTIClist=1%2C4&SearchText=Canada"


@dataclass(frozen=True)
class AnnualCorrectionsStatistic:
    fiscal_year: str
    total_in_custody: int
    indigenous_in_custody: int
    indigenous_in_custody_percent: float
    non_indigenous_in_custody: int
    not_readmitted_five_years_percent: float
    recidivism_rate_percent: float
    care_and_custody_spending: int
    cost_per_inmate: int


@dataclass(frozen=True)
class OCIHighlight:
    title: str
    summary: str
    source_url: str


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "corrections-statistics",
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
    logger = logging.getLogger("corrections-statistics")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def build_statistics() -> dict[str, object]:
    annual_statistics = [
        _annual_statistic(
            fiscal_year="2021 to 2022",
            indigenous_in_custody=4028,
            non_indigenous_in_custody=8300,
            not_readmitted_five_years_percent=87.9,
            care_and_custody_spending=1_862_657_518,
        ),
        _annual_statistic(
            fiscal_year="2022 to 2023",
            indigenous_in_custody=4223,
            non_indigenous_in_custody=8831,
            not_readmitted_five_years_percent=88.6,
            care_and_custody_spending=1_941_837_555,
        ),
        _annual_statistic(
            fiscal_year="2023 to 2024",
            indigenous_in_custody=4579,
            non_indigenous_in_custody=9276,
            not_readmitted_five_years_percent=89.9,
            care_and_custody_spending=2_119_199_375,
        ),
    ]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "reference_fiscal_year": annual_statistics[-1].fiscal_year,
        "source": {
            "title": "CSC Departmental Results Report and Indigenous Corrections Accountability Framework",
            "url": CSC_DRR_2023_2024_URL,
            "note": "In-custody population and Indigenous representation use CSC ICAF; recidivism and spending use CSC Departmental Results Reports.",
        },
        "sources": [
            {
                "title": "Correctional Service Canada Departmental Results Report 2023-2024",
                "url": CSC_DRR_2023_2024_URL,
                "note": "Five-year non-readmission indicator and Care and Custody spending.",
            },
            {
                "title": "Correctional Service Canada Indigenous Corrections Accountability Framework 2023-2024",
                "url": CSC_ICAF_2023_2024_URL,
                "note": "In-custody Indigenous and non-Indigenous population trend.",
            },
            {
                "title": "Office of the Correctional Investigator Annual Report 2024-2025",
                "url": OCI_ANNUAL_REPORT_2024_2025_URL,
                "note": "Independent annual report highlights relevant to federal corrections debates.",
            },
            {
                "title": "Statistics Canada 2021 Census Profile",
                "url": STATCAN_CENSUS_PROFILE_URL,
                "note": "National Indigenous population share for comparison.",
            },
        ],
        "indigenous_population_share": {
            "year": "2021",
            "population": 1_807_250,
            "percent_of_canada": 5.0,
            "source_title": "Statistics Canada 2021 Census Profile",
            "source_url": STATCAN_CENSUS_PROFILE_URL,
        },
        "annual_statistics": [asdict(item) for item in annual_statistics],
        "oci_highlights": [asdict(item) for item in _oci_highlights()],
    }


def _annual_statistic(
    *,
    fiscal_year: str,
    indigenous_in_custody: int,
    non_indigenous_in_custody: int,
    not_readmitted_five_years_percent: float,
    care_and_custody_spending: int,
) -> AnnualCorrectionsStatistic:
    total_in_custody = indigenous_in_custody + non_indigenous_in_custody
    indigenous_percent = round(indigenous_in_custody / total_in_custody * 100, 1)
    return AnnualCorrectionsStatistic(
        fiscal_year=fiscal_year,
        total_in_custody=total_in_custody,
        indigenous_in_custody=indigenous_in_custody,
        indigenous_in_custody_percent=indigenous_percent,
        non_indigenous_in_custody=non_indigenous_in_custody,
        not_readmitted_five_years_percent=not_readmitted_five_years_percent,
        recidivism_rate_percent=round(100 - not_readmitted_five_years_percent, 1),
        care_and_custody_spending=care_and_custody_spending,
        cost_per_inmate=round(care_and_custody_spending / total_in_custody),
    )


def _oci_highlights() -> list[OCIHighlight]:
    return [
        OCIHighlight(
            title="Indigenous people account for about one third of federal custody",
            summary="OCI's 2024-2025 annual report describes Indigenous people as approximately one third of individuals in federal custody, with complex and disproportionate health needs.",
            source_url=OCI_ANNUAL_REPORT_2024_2025_URL,
        ),
        OCIHighlight(
            title="Culturally informed mental health services are limited",
            summary="OCI highlights gaps in trauma-informed and culturally informed mental health care for Indigenous prisoners, including limited access to appropriate practitioners and continuity of care on release.",
            source_url=OCI_ANNUAL_REPORT_2024_2025_URL,
        ),
        OCIHighlight(
            title="Healing Lodge access remains narrow",
            summary="OCI reports that Healing Lodges are accessible to only a small fraction of the Indigenous population in custody, largely for people nearing sentence end.",
            source_url=OCI_ANNUAL_REPORT_2024_2025_URL,
        ),
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="Path to write JSON snapshot.")
    parser.add_argument("--dry-run", action="store_true", help="Write JSON to stdout instead of output path.")
    args = parser.parse_args(argv)

    logger = configure_logging()
    started = time.monotonic()
    logger.info("pipeline started", extra={"dry_run": args.dry_run, "output": args.output})
    try:
        snapshot = build_statistics()
    except Exception as exc:
        logger.error("snapshot build failed", extra={"error": f"{type(exc).__name__}: {exc}"})
        raise
    payload = json.dumps(snapshot, indent=2, sort_keys=True) + "\n"
    if args.dry_run:
        sys.stdout.write(payload)
    else:
        with open(args.output, "w", encoding="utf-8") as output:
            output.write(payload)
    elapsed_ms = int((time.monotonic() - started) * 1000)
    logger.info("pipeline finished", extra={"records_processed": len(snapshot["annual_statistics"]), "duration_ms": elapsed_ms})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
