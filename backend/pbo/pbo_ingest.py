#!/usr/bin/env python3
"""Scrape the Parliamentary Budget Officer publication index and emit JSON.

Authoritative source: https://www.pbo-dpb.ca/en/publications

This script is an 'extractor' — it fetches and parses PBO publication metadata
and emits a JSON array to stdout. It uses only the Python standard library.

Usage:
    # Emit all publications as JSON to stdout
    python pbo_ingest.py

    # Incremental daily run: only fetch the first page
    python pbo_ingest.py --no-backfill
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import ssl
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


BASE_URL = "https://www.pbo-dpb.ca"
PUBLICATIONS_PATH = "/en/publications"
PIPELINE_NAME = "pbo-publications"
API_ROOT_FALLBACK = "https://rest-393962616e6b.pbo-dpb.ca/"

# Maps PBO category labels (lowercased) to normalized methodology_category values.
_CATEGORY_MAP: dict[str, str] = {
    "legislative costing": "legislative-cost",
    "legislative cost": "legislative-cost",
    "fiscal analysis": "fiscal-update",
    "fiscal update": "fiscal-update",
    "fiscal": "fiscal-update",
    "economic and fiscal outlook": "fiscal-update",
    "estimates": "fiscal-update",
    "election platform costing": "election-platform",
    "election platform": "election-platform",
    "program evaluation": "program-evaluation",
    "program assessment": "program-evaluation",
}


class _JSONFormatter(logging.Formatter):
    """Stdlib-only JSON log formatter — one JSON object per record to stderr."""

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
class PBOPublication:
    id: str                              # slug from source URL path
    title: str
    publication_date: Optional[str]      # ISO-8601 date string or None
    methodology_category: Optional[str]  # normalized category or None
    source_url: str
    pdf_url: Optional[str]
    summary_text: Optional[str]          # verbatim from page
    content_hash: str                    # SHA-256 of title + publication_date


def _fetch(url: str, timeout: int = 30) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": "epac-pbo-ingest/1.0 (epac.riddimsoftware.com; contact: sunny@riddimsoftware.com)",
            "Accept": "text/html,application/xhtml+xml,application/json",
            "Accept-Language": "en-CA,en;q=0.9",
        },
    )
    # Use default context to leverage system trust store (fixes brittle hardcoded paths)
    ctx = ssl.create_default_context()
    with urlopen(request, timeout=timeout, context=ctx) as response:
        return response.read().decode("utf-8", errors="replace")


def _content_hash(title: str, publication_date: Optional[str]) -> str:
    raw = f"{title}|{publication_date or ''}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _normalize_category(raw_type: str, title: str, abstract: str) -> Optional[str]:
    """Map PBO type and keywords to normalized methodology_category."""
    # 1. Explicit type mapping
    if raw_type in ("LEG", "ES"):
        return "legislative-cost"

    # 2. Keyword mapping on title and abstract
    text = f"{title} {abstract}".lower()
    for fragment, normalized in _CATEGORY_MAP.items():
        if fragment in text:
            return normalized

    # 3. Fallback
    return "other" if raw_type else None


def _get_api_root() -> str:
    """Extract the current API root from the publications page HTML."""
    try:
        html = _fetch(f"{BASE_URL}{PUBLICATIONS_PATH}")
        # Look for data-apiroot="https://rest-..."
        match = re.search(r'data-apiroot="([^"]+)"', html)
        if match:
            return match.group(1).rstrip("/") + "/"
    except Exception as exc:
        logger.warning("failed to extract apiroot from HTML, using fallback", extra={"error": str(exc)})
    return API_ROOT_FALLBACK


def fetch_publications(backfill: bool = True) -> list[PBOPublication]:
    """Fetch all publication records from the PBO JSON API."""
    api_root = _get_api_root()
    publications: list[PBOPublication] = []
    url: Optional[str] = f"{api_root}publications"

    while url:
        logger.info("fetching page", extra={"url": url})
        try:
            resp_json = json.loads(_fetch(url))
        except (HTTPError, URLError, json.JSONDecodeError) as exc:
            logger.error("api fetch failed", extra={"url": url, "error": str(exc)})
            break

        data = resp_json.get("data", [])
        for item in data:
            title = item.get("title_en", "")
            release_date = item.get("release_date")
            if release_date:
                # Extract YYYY-MM-DD from ISO-8601
                release_date = release_date.split("T")[0]

            metadata = item.get("metadata", {})
            abstract = metadata.get("abstract_en", "")
            raw_type = item.get("type", "")
            slug = item.get("slug", "")

            # PDF URL
            pdf_url = item.get("artifacts", {}).get("main", {}).get("en", {}).get("public")

            # Source URL
            source_url = item.get("permalinks", {}).get("en", {}).get("website")
            if not source_url:
                source_url = f"{BASE_URL}/en/publications/{slug}"

            pub = PBOPublication(
                id=slug,
                title=title,
                publication_date=release_date,
                methodology_category=_normalize_category(raw_type, title, abstract),
                source_url=source_url,
                pdf_url=pdf_url,
                summary_text=abstract if abstract else None,
                content_hash=_content_hash(title, release_date),
            )
            if pub.title:
                publications.append(pub)

        if not backfill:
            break

        url = resp_json.get("links", {}).get("next")
        if url:
            time.sleep(0.2)  # polite delay

    return publications


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backfill",
        action="store_true",
        default=True,
        help="Fetch all pages (default).",
    )
    parser.add_argument(
        "--no-backfill",
        dest="backfill",
        action="store_false",
        help="Only fetch the first page (daily incremental mode)",
    )
    args = parser.parse_args(argv)

    started_at = time.monotonic()
    logger.info("pipeline started", extra={"backfill": args.backfill})

    # Fetch and parse publications from the JSON API
    try:
        publications = fetch_publications(backfill=args.backfill)
    except Exception as exc:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        err = f"{type(exc).__name__}: {exc}"
        logger.error(
            "pipeline failed",
            extra={"error": err, "duration_ms": duration_ms},
        )
        return 2

    logger.info("publications fetched and parsed", extra={"count": len(publications)})

    if not publications:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        err = "ParseError: zero publications found — PBO API structure may have changed"
        logger.error(err, extra={"error": err, "duration_ms": duration_ms})
        return 3

    # Emit JSON to stdout
    sys.stdout.write(json.dumps([asdict(pub) for pub in publications], indent=2, ensure_ascii=False))
    sys.stdout.write("\n")
    
    duration_ms = int((time.monotonic() - started_at) * 1000)
    logger.info("pipeline finished", extra={"records_processed": len(publications), "duration_ms": duration_ms})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
