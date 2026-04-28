#!/usr/bin/env python3
"""Fetch and parse Finance Canada's Fiscal Monitor HTML pages.

The source pages are official Department of Finance Canada publications:
https://www.canada.ca/en/department-finance/services/publications/fiscal-monitor.html
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date
from html.parser import HTMLParser
import json
import os
import re
import ssl
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from observability.logger import get_logger

logger = get_logger("fiscal_monitor")

BASE_URL = "https://www.canada.ca"


@dataclass(frozen=True)
class FiscalMonitorEntry:
    id: str
    fiscal_year: str
    month: str
    publication_date: str
    revenue_millions: float
    expense_millions: float
    budgetary_balance_millions: float
    year_to_date_balance_millions: float
    annual_budget_projection_millions: float | None
    source_title: str
    source_url: str


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def text(self) -> str:
        return re.sub(r"\s+", " ", " ".join(self.parts)).strip()


def current_fiscal_year_issue_urls(today: date | None = None) -> list[str]:
    today = today or date.today()
    fiscal_start_year = today.year - 1 if today.month <= 6 else today.year
    months = [(fiscal_start_year, month) for month in range(4, 13)]
    months.extend((fiscal_start_year + 1, month) for month in range(1, 4))
    return [
        f"{BASE_URL}/en/department-finance/services/publications/fiscal-monitor/{year:04d}/{month:02d}.html"
        for year, month in months
    ]


def parse_issue_html(html: str, source_url: str) -> FiscalMonitorEntry:
    extractor = TextExtractor()
    extractor.feed(html)
    text = extractor.text()

    issue_match = re.search(r"Fiscal Monitor - ([A-Za-z]+) (\d{4})", text)
    if not issue_match:
        raise ValueError("Fiscal Monitor issue month not found")
    month_name, year_text = issue_match.groups()
    month_number = _month_number(month_name)
    year = int(year_text)

    publication_match = re.search(r"Page details (\d{4}-\d{2}-\d{2})", text)
    if not publication_match:
        raise ValueError("publication date not found")

    revenue_current, _revenue_ytd = _last_two_numbers_between(text, r"Revenues", r"Expenses")
    balance_current, balance_ytd = _last_two_numbers_between(
        text,
        r"Budgetary balance \(deficit/surplus\)",
        r"Non-budgetary transactions",
    )
    expense_current = revenue_current - balance_current
    projection = _annual_budget_projection(text)
    source_url = _pdf_source_url(html) or source_url

    fiscal_start = year if month_number >= 4 else year - 1
    fiscal_year = f"{fiscal_start}-{(fiscal_start + 1) % 100:02d}"
    issue_id = f"{year:04d}-{month_number:02d}"
    source_title = f"Finance Canada Fiscal Monitor, {month_name} {year}"

    return FiscalMonitorEntry(
        id=issue_id,
        fiscal_year=fiscal_year,
        month=issue_id,
        publication_date=publication_match.group(1),
        revenue_millions=revenue_current,
        expense_millions=expense_current,
        budgetary_balance_millions=balance_current,
        year_to_date_balance_millions=balance_ytd,
        annual_budget_projection_millions=projection,
        source_title=source_title,
        source_url=source_url,
    )


def fetch_current_fiscal_year() -> list[FiscalMonitorEntry]:
    entries: list[FiscalMonitorEntry] = []
    context = _ssl_context()
    for url in current_fiscal_year_issue_urls():
        request = Request(url, headers={"Accept": "text/html", "User-Agent": "epac-fiscal-monitor"})
        try:
            with urlopen(request, timeout=10, context=context) as response:
                html = response.read().decode("utf-8")
        except HTTPError as exc:
            if exc.code == 404:
                # 404 is the expected signal that the issue isn't published yet.
                continue
            logger.exception("fetch.http_error", extra={"url": url, "status_code": exc.code})
            raise
        except (TimeoutError, URLError):
            logger.warning("fetch.network_error", extra={"url": url})
            continue
        entries.append(parse_issue_html(html, url))
    return sorted(entries, key=lambda entry: entry.month)


def _ssl_context() -> ssl.SSLContext:
    for cafile in ("/etc/ssl/cert.pem", "/opt/homebrew/etc/ca-certificates/cert.pem"):
        try:
            return ssl.create_default_context(cafile=cafile)
        except FileNotFoundError:
            continue
    return ssl.create_default_context()


def _annual_budget_projection(text: str) -> float | None:
    match = re.search(r"Actual/projected annual budgetary balance (.*?) Table 1", text)
    if not match:
        return None
    numbers = _numbers(match.group(1))
    if len(numbers) >= 3 and numbers[0] == 1:
        return numbers[2]
    return numbers[1] if len(numbers) >= 2 else None


def _pdf_source_url(html: str) -> str | None:
    match = re.search(r'href="([^"]+\.pdf)"', html, flags=re.IGNORECASE)
    if not match:
        return None
    href = match.group(1)
    return href if href.startswith("http") else f"{BASE_URL}{href}"


def _last_two_numbers_between(text: str, start: str, end: str) -> tuple[float, float]:
    match = re.search(fr"{start} (.*?) {end}", text)
    if not match:
        raise ValueError(f"section not found: {start}")
    numbers = _numbers(match.group(1))
    if len(numbers) < 4:
        raise ValueError(f"not enough numbers in section: {start}")
    return numbers[1], numbers[3]


def _numbers(text: str) -> list[float]:
    values: list[float] = []
    for token in re.findall(r"-?\d{1,3}(?:,\d{3})*|-", text):
        values.append(0.0 if token == "-" else float(token.replace(",", "")))
    return values


def _month_number(month_name: str) -> int:
    months = [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ]
    return months.index(month_name) + 1


def main() -> int:
    started = time.monotonic()
    logger.info("pipeline.start", extra={"source": "canada.ca/fiscal-monitor"})
    entries = fetch_current_fiscal_year()
    json.dump([asdict(entry) for entry in entries], sys.stdout, indent=2)
    sys.stdout.write("\n")
    duration_ms = int((time.monotonic() - started) * 1000)
    logger.info("pipeline.done", extra={"records_processed": len(entries), "duration_ms": duration_ms})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
