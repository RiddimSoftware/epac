#!/usr/bin/env python3
"""Scrape the Parliamentary Budget Officer publication index and upsert to Postgres.

Authoritative source: https://www.pbo-dpb.ca/en/publications

Each run is idempotent: new publications are inserted; existing publications whose
title or date have changed (detected via SHA-256 hash) are updated. Re-running
the full backfill is always safe.

Environment variables:
    DATABASE_URL   Postgres DSN (required unless --dry-run is set)

Usage:
    # Dry-run: print records as JSON to stdout, no DB writes
    python pbo_ingest.py --dry-run

    # Normal run: upsert all publications into Postgres
    DATABASE_URL="postgresql://..." python pbo_ingest.py

    # Backfill: same as normal run; the scraper always fetches all pages
    DATABASE_URL="postgresql://..." python pbo_ingest.py --backfill
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import ssl
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
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


def _ssl_context() -> ssl.SSLContext:
    for cafile in ("/etc/ssl/cert.pem", "/opt/homebrew/etc/ca-certificates/cert.pem"):
        try:
            return ssl.create_default_context(cafile=cafile)
        except FileNotFoundError:
            continue
    return ssl.create_default_context()


def _fetch(url: str, timeout: int = 30) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": "epac-pbo-ingest/1.0 (epac.riddimsoftware.com; contact: sunny@riddimsoftware.com)",
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-CA,en;q=0.9",
        },
    )
    ctx = _ssl_context()
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


def upsert_publications(publications: list[PBOPublication], db_url: str) -> int:
    """Upsert publication records into Postgres. Returns the number of rows affected."""
    try:
        import psycopg2  # type: ignore[import]
        import psycopg2.extras  # type: ignore[import]
    except ImportError:
        logger.error(
            "psycopg2 not installed — install psycopg2-binary and retry",
            extra={"error": "ImportError: psycopg2"},
        )
        raise

    conn = psycopg2.connect(db_url)
    try:
        with conn:
            with conn.cursor() as cur:
                count = 0
                for pub in publications:
                    cur.execute(
                        """
                        INSERT INTO pbo_publications
                            (id, title, publication_date, methodology_category,
                             source_url, pdf_url, summary_text, content_hash, ingested_at)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
                        ON CONFLICT (source_url) DO UPDATE SET
                            title                = EXCLUDED.title,
                            publication_date     = EXCLUDED.publication_date,
                            methodology_category = EXCLUDED.methodology_category,
                            pdf_url              = EXCLUDED.pdf_url,
                            summary_text         = EXCLUDED.summary_text,
                            content_hash         = EXCLUDED.content_hash,
                            ingested_at          = NOW()
                        WHERE pbo_publications.content_hash <> EXCLUDED.content_hash
                           OR pbo_publications.pdf_url IS DISTINCT FROM EXCLUDED.pdf_url
                           OR pbo_publications.summary_text IS DISTINCT FROM EXCLUDED.summary_text
                        """,
                        (
                            pub.id,
                            pub.title,
                            pub.publication_date,
                            pub.methodology_category,
                            pub.source_url,
                            pub.pdf_url,
                            pub.summary_text,
                            pub.content_hash,
                        ),
                    )
                    count += cur.rowcount
        return count
    finally:
        conn.close()


def record_health(db_url: str, count: int, error: Optional[str]) -> None:
    try:
        import psycopg2  # type: ignore[import]
    except ImportError:
        return
    conn = psycopg2.connect(db_url)
    try:
        now = datetime.now(timezone.utc)
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO pipeline_health
                        (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
                    VALUES (%s, %s, %s, %s, %s, 24)
                    ON CONFLICT (name) DO UPDATE SET
                        last_run_at     = EXCLUDED.last_run_at,
                        last_success_at = COALESCE(
                            CASE WHEN EXCLUDED.last_error IS NULL THEN EXCLUDED.last_success_at END,
                            pipeline_health.last_success_at
                        ),
                        last_error      = EXCLUDED.last_error,
                        record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
                    """,
                    (
                        PIPELINE_NAME,
                        now,
                        now if error is None else None,
                        error,
                        count if error is None else None,
                    ),
                )
    finally:
        conn.close()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch and parse publications but print JSON to stdout instead of writing to Postgres",
    )
    parser.add_argument(
        "--backfill",
        action="store_true",
        default=True,
        help="Fetch all pages (default). Pass --no-backfill for incremental daily runs.",
    )
    parser.add_argument(
        "--no-backfill",
        dest="backfill",
        action="store_false",
        help="Only fetch the first page (daily incremental mode)",
    )
    args = parser.parse_args(argv)

    started_at = time.monotonic()
    logger.info("pipeline started", extra={"dry_run": args.dry_run, "backfill": args.backfill})

    db_url = os.environ.get("DATABASE_URL", "")
    if not args.dry_run and not db_url:
        logger.error(
            "DATABASE_URL is not set",
            extra={"error": "EnvironmentError: DATABASE_URL required when not in dry-run mode"},
        )
        return 1

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
        if not args.dry_run and db_url:
            record_health(db_url, 0, err)
        return 2

    logger.info("publications fetched and parsed", extra={"count": len(publications)})

    if not publications:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        err = "ParseError: zero publications found — PBO API structure may have changed"
        logger.error(err, extra={"error": err, "duration_ms": duration_ms})
        if not args.dry_run and db_url:
            record_health(db_url, 0, err)
        return 3

    if args.dry_run:
        sys.stdout.write(json.dumps([asdict(pub) for pub in publications], indent=2, ensure_ascii=False))
        sys.stdout.write("\n")
        duration_ms = int((time.monotonic() - started_at) * 1000)
        logger.info("pipeline finished", extra={"records_processed": len(publications), "duration_ms": duration_ms})
        return 0

    # Upsert to Postgres
    try:
        upserted = upsert_publications(publications, db_url)
    except Exception as exc:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        err = f"{type(exc).__name__}: {exc}"
        logger.error(
            "database upsert failed",
            extra={"error": err, "duration_ms": duration_ms},
        )
        record_health(db_url, 0, err)
        return 4

    duration_ms = int((time.monotonic() - started_at) * 1000)
    logger.info(
        "pipeline finished",
        extra={
            "records_processed": len(publications),
            "records_upserted": upserted,
            "duration_ms": duration_ms,
        },
    )
    record_health(db_url, len(publications), None)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
