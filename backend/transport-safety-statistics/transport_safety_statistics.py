#!/usr/bin/env python3
"""Fetch national transportation safety and road casualty statistics.

TSB annual statistics cover air, marine, and rail occurrences. Transport
Canada's Canadian Motor Vehicle Traffic Collision Statistics provide road
fatality and injury rates by province and national casualty counts.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
import argparse
import json
import logging
import re
import ssl
import sys
import time
from urllib.request import Request, urlopen


LATEST_TSB_YEAR = 2024
LATEST_ROAD_YEAR = 2023
HISTORY_YEARS = 5

TSB_MODE_URLS = {
    "air": "https://www.tsb.gc.ca/eng/stats/aviation/{year}/ssea-ssao-{year}.html",
    "marine": "https://www.tsb.gc.ca/eng/stats/marine/{year}/ssem-ssmo-{year}.html",
    "rail": "https://www.tsb.gc.ca/eng/stats/rail/{year}/sser-ssro-{year}.html",
}

ROAD_URL = (
    "https://tc.canada.ca/en/road-transportation/statistics-data/"
    "canadian-motor-vehicle-traffic-collision-statistics/{year}/"
    "canadian-motor-vehicle-traffic-collision-statistics-{year}"
)
TSB_ANNUAL_INDEX_URL = "https://tsb.gc.ca/eng/stats/aviation/stats.html"

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


@dataclass(frozen=True)
class ModeYear:
    year: int
    occurrences: int
    accidents: int
    incidents: int
    fatalities: int
    source_url: str


@dataclass(frozen=True)
class RoadNationalYear:
    year: int
    fatalities: int
    serious_injuries: int
    total_injuries: int
    source_url: str


@dataclass(frozen=True)
class RoadProvinceYear:
    year: int
    fatalities_per_100k: float
    injuries_per_100k: float
    fatalities_per_billion_vkt: float
    injuries_per_billion_vkt: float
    fatalities_per_100k_licensed_drivers: float
    injuries_per_100k_licensed_drivers: float
    source_url: str


@dataclass(frozen=True)
class RoadProvinceStatistic:
    province: str
    province_code: str
    reference_year: int
    fatalities_per_100k: float
    injuries_per_100k: float
    fatalities_per_billion_vkt: float
    history: list[RoadProvinceYear]


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        cleaned = data.strip()
        if cleaned:
            self.parts.append(cleaned)

    def text(self) -> str:
        return " ".join(self.parts)


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": "transport-safety-statistics",
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
    logger = logging.getLogger("transport-safety-statistics")
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


def fetch_text(url: str) -> str:
    request = Request(url, headers={"User-Agent": "epac-transport-safety-statistics"})
    with urlopen(request, timeout=30, context=_ssl_context()) as response:
        html = response.read().decode("utf-8", errors="replace")
    parser = TextExtractor()
    parser.feed(html)
    return _normalize_text(parser.text())


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\xa0", " ")).strip()


def _to_int(value: str) -> int:
    return int(value.replace(",", ""))


def _first_int(patterns: list[str], text: str, label: str) -> int:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            return _to_int(match.group(1))
    raise ValueError(f"could not parse {label}")


def _air_incidents_from_type_table(year: int, text: str) -> int:
    marker = f"Reported air transportation incidents, by type, {year}"
    start = text.find(marker)
    if start == -1:
        raise ValueError(f"could not locate air incidents type table {year}")
    table = text[start:start + 800]
    matches = re.findall(
        r"(?:Declared emergency|Risk of collision / Loss of separation|Engine failure|Smoke / Fire|Collision|Other incident type)\s+([0-9,]+)\s+[0-9.]+%",
        table,
        flags=re.IGNORECASE,
    )
    if len(matches) != 6:
        raise ValueError(f"could not parse air incidents type table {year}")
    return sum(_to_int(item) for item in matches)


def parse_mode_year(mode: str, year: int, text: str, source_url: str) -> ModeYear:
    if mode == "air":
        accidents = _first_int([
            r"\(([0-9,]+) accidents and [0-9,]+ incidents\)",
            rf"([0-9,]+) air transportation accidents were reported .*?{year}",
            rf"In {year}, a total of ([0-9,]+) air transportation accidents were reported",
        ], text, f"{mode} accidents {year}")
        try:
            incidents = _first_int([
                r"\([0-9,]+ accidents and ([0-9,]+) incidents\)",
                r"remaining ([0-9,]+) reports were aviation incidents",
            ], text, f"{mode} incidents {year}")
        except ValueError:
            incidents = _air_incidents_from_type_table(year, text)
        try:
            occurrences = _first_int([
                r"received ([0-9,]+) reports of air occurrences",
                r"received ([0-9,]+) reports? .*?air occurrences",
            ], text, f"{mode} occurrences {year}")
        except ValueError:
            occurrences = accidents + incidents
        fatalities = _first_int([
            r"including ([0-9,]+) fatalities",
            r"resulting in ([0-9,]+) fatalities",
            rf"([0-9,]+) fatalities in {year}",
        ], text, f"{mode} fatalities {year}")
    elif mode == "marine":
        accidents = _first_int([
            r"Of these, ([0-9,]+) were accidents",
            r"Of the [0-9,]+ reports received, ([0-9,]+) were accidents",
            rf"In {year}, ([0-9,]+) marine accidents .*?were reported",
        ], text, f"{mode} accidents {year}")
        fatalities = _first_int([
            r"total of ([0-9,]+) fatalities",
            r"resulting in ([0-9,]+) fatalities",
            r"with ([0-9,]+) fatalities",
            rf"In {year}, ([0-9,]+) marine fatalities were reported",
        ], text, f"{mode} fatalities {year}")
        try:
            occurrences = _first_int([
                r"received ([0-9,]+) reports of marine occurrences",
            ], text, f"{mode} occurrences {year}")
            incidents = occurrences - accidents
        except ValueError:
            incidents = _first_int([
                rf"In {year}, ([0-9,]+) marine incidents were reported",
            ], text, f"{mode} incidents {year}")
            occurrences = accidents + incidents
    elif mode == "rail":
        accidents = _first_int([
            r"Of these, ([0-9,]+) were accidents",
            r"Of the [0-9,]+ reports received, ([0-9,]+) were accidents",
            rf"In {year}, ([0-9,]+).{{0,80}}rail accidents.{{0,80}}were reported",
        ], text, f"{mode} accidents {year}")
        fatalities = _first_int([
            r"There were ([0-9,]+) fatalities",
            r"resulted in ([0-9,]+) fatalities",
            rf"Rail fatalities .*? totalled ([0-9,]+) in {year}",
        ], text, f"{mode} fatalities {year}")
        try:
            occurrences = _first_int([
                r"received ([0-9,]+) reports of rail occurrences",
            ], text, f"{mode} occurrences {year}")
            incidents = occurrences - accidents
        except ValueError:
            incidents = _first_int([
                rf"In {year}, there were ([0-9,]+) reported rail incidents",
            ], text, f"{mode} incidents {year}")
            occurrences = accidents + incidents
    else:
        raise ValueError(f"unsupported mode {mode}")

    return ModeYear(
        year=year,
        occurrences=occurrences,
        accidents=accidents,
        incidents=incidents,
        fatalities=fatalities,
        source_url=source_url,
    )


def parse_road_year(year: int, text: str, source_url: str) -> tuple[RoadNationalYear, dict[str, RoadProvinceYear]]:
    national_pattern = rf"\b{year}\s+([0-9,]+)\s+([0-9,]+)\s+([0-9,]+)\s+([0-9,]+)\s+([0-9,]+)\b"
    national_match = re.search(national_pattern, text)
    if not national_match:
        raise ValueError(f"could not parse national road casualties {year}")

    national = RoadNationalYear(
        year=year,
        fatalities=_to_int(national_match.group(3)),
        serious_injuries=_to_int(national_match.group(4)),
        total_injuries=_to_int(national_match.group(5)),
        source_url=source_url,
    )

    marker = f"Casualty Rates - {year}"
    if marker not in text:
        raise ValueError(f"could not locate casualty rate table {year}")
    table_text = text[text.index(marker):]

    province_years: dict[str, RoadProvinceYear] = {}
    for code in PROVINCE_DISPLAY_NAMES:
        pattern = rf"\b{code}\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\b"
        match = re.search(pattern, table_text)
        if not match:
            raise ValueError(f"could not parse {code} road casualty rates {year}")
        province_years[code] = RoadProvinceYear(
            year=year,
            fatalities_per_100k=float(match.group(1)),
            injuries_per_100k=float(match.group(2)),
            fatalities_per_billion_vkt=float(match.group(3)),
            injuries_per_billion_vkt=float(match.group(4)),
            fatalities_per_100k_licensed_drivers=float(match.group(5)),
            injuries_per_100k_licensed_drivers=float(match.group(6)),
            source_url=source_url,
        )

    return national, province_years


def build_payload(fetcher=fetch_text) -> dict[str, object]:
    tsb_years = list(range(LATEST_TSB_YEAR - HISTORY_YEARS + 1, LATEST_TSB_YEAR + 1))
    road_years = list(range(LATEST_ROAD_YEAR - HISTORY_YEARS + 1, LATEST_ROAD_YEAR + 1))

    modes: dict[str, list[ModeYear]] = {}
    for mode, template in TSB_MODE_URLS.items():
        records: list[ModeYear] = []
        for year in tsb_years:
            url = template.format(year=year)
            records.append(parse_mode_year(mode, year, fetcher(url), url))
        modes[mode] = records

    road_national: list[RoadNationalYear] = []
    road_by_province_year: dict[str, list[RoadProvinceYear]] = {
        code: [] for code in PROVINCE_DISPLAY_NAMES
    }
    for year in road_years:
        url = ROAD_URL.format(year=year)
        national, province_years = parse_road_year(year, fetcher(url), url)
        road_national.append(national)
        for code, record in province_years.items():
            road_by_province_year[code].append(record)

    provinces: list[RoadProvinceStatistic] = []
    for code, history in road_by_province_year.items():
        latest = max(history, key=lambda item: item.year)
        provinces.append(
            RoadProvinceStatistic(
                province=PROVINCE_DISPLAY_NAMES[code],
                province_code=code,
                reference_year=latest.year,
                fatalities_per_100k=latest.fatalities_per_100k,
                injuries_per_100k=latest.injuries_per_100k,
                fatalities_per_billion_vkt=latest.fatalities_per_billion_vkt,
                history=history,
            )
        )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "title": "TSB Annual Statistics and Transport Canada Road Safety",
            "url": TSB_ANNUAL_INDEX_URL,
            "note": (
                "TSB annual summaries report air, marine, and rail occurrences. "
                "Transport Canada's National Collision Database reports road casualty rates "
                "by province and national casualty counts."
            ),
        },
        "datasets": [
            {
                "id": "tsb-annual-statistics",
                "title": "Transportation Safety Board of Canada Annual Statistics",
                "url": TSB_ANNUAL_INDEX_URL,
            },
            {
                "id": "tc-road-collision-statistics",
                "title": "Transport Canada Canadian Motor Vehicle Traffic Collision Statistics",
                "url": ROAD_URL.format(year=LATEST_ROAD_YEAR),
            },
        ],
        "history_years": {
            "tsb": tsb_years,
            "road": road_years,
        },
        "modes": {mode: [asdict(item) for item in records] for mode, records in modes.items()},
        "road": {
            "national": [asdict(item) for item in road_national],
            "provinces": [asdict(item) for item in provinces],
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fetch transportation safety statistics")
    parser.add_argument("--output", help="Write JSON to a file instead of stdout")
    args = parser.parse_args(argv)

    logger = configure_logging()
    start = time.monotonic()
    logger.info("pipeline started", extra={"output": args.output or "stdout"})
    try:
        payload = build_payload()
    except Exception as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        logger.error(
            "fetch failed from transportation safety source",
            extra={
                "error": f"{type(exc).__name__}: {exc}",
                "url": f"{TSB_ANNUAL_INDEX_URL} | {ROAD_URL.format(year=LATEST_ROAD_YEAR)}",
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
            "records_processed": len(payload["road"]["provinces"]),
            "history_years": payload["history_years"],
            "duration_ms": duration_ms,
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
