#!/usr/bin/env python3
"""Fetch the OCL subject-matter controlled vocabulary and emit JSON to stdout.

Authoritative source: https://lobbycanada.gc.ca (Office of the Commissioner of
Lobbying of Canada). The "Subject Matter in Active Registrations" report
(`/app/secure/ocl/lrs/do/regSms`) lists every active subject-matter code along
with the integer `ocl_code` used in advanced-search URLs. English labels come
from `?lang=eng`; French labels come from `?lang=fra`; the two views are joined
by `ocl_code`.

This script is an extractor — it fetches and parses the live vocabulary, and
emits a JSON array to stdout for the Go loader to upsert into the
`lobbyist_subject_matter_codes` table (see migration
`backend/migrations/013_lobbyist_subject_matter_codes.sql`). The table is
named `lobbyist_subject_matter_codes` rather than the original
`lobbyist_subject_matters` from EPAC-2149's acceptance criteria because
EPAC-2150 merged ahead and took that name for a per-record junction table.

Usage:
    python3 backend/lobbying/subject_matters_ingest.py            # write JSON to stdout
    python3 backend/lobbying/subject_matters_ingest.py --report   # also refresh mapping_report.md
"""

from __future__ import annotations

import argparse
import html
import json
import logging
import re
import ssl
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PIPELINE_NAME = "lobbyist-subject-matters"
BASE_URL = "https://lobbycanada.gc.ca"
REG_SUBJECTS_PATH = "/app/secure/ocl/lrs/do/regSms"
COMM_SUBJECTS_PATH = "/app/secure/ocl/lrs/do/cmmLgSms"
REPORT_RELATIVE_PATH = "backend/lobbying/mapping_report.md"
USER_AGENT = (
    "epac-lobbying-ingest/1.0 (epac.riddimsoftware.com; "
    "contact: sunny@riddimsoftware.com)"
)


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
class OCLSubjectMatter:
    ocl_code: int
    label_en: str
    label_fr: str
    active: bool = True


# Subject-matter rows on regSms look like:
#   <tr>
#     <td>Agriculture</td>
#     <td class="text-right">
#       <a href="...adv_2001_subjectMatter=3...">798</a>
#     </td>
#     ...
#   </tr>
# The first <td> holds the label; the link's query string carries the integer
# `ocl_code`. We only need the first column-pair on each row — the same code
# appears repeatedly in trend columns and we deduplicate by `ocl_code`.
_SUBJECT_ROW_RE = re.compile(
    r"<tr>\s*<td>\s*([^<\n]+?)\s*</td>\s*"
    r"<td[^>]*>\s*(?:<a[^>]*adv_2001_subjectMatter=(\d+)[^\"]*\"[^>]*>)",
    re.DOTALL,
)

# cmmLgSms publishes two tables we care about:
#   1. The selected-period table (top) lists the most recent reporting month
#      via <a href="...rcntSmCmLgs?cid=N&dt=YYYY-MM">count</a>.
#   2. The "Last Six Completed Reporting Periods" trend table (bottom) repeats
#      every code with one anchor per month: <a href="...rcntSmCmLgs?dt=YYYY-MM
#      &cid=N&tb=historical">count</a>.
# We extract every (cid, dt) pair and dedupe by (cid, dt) so the overlapping
# current month is not double-counted. Order of cid/dt in the URL varies.
_COMM_CELL_RE = re.compile(
    r"<a[^>]*rcntSmCmLgs\?(?P<query>[^\"]+)\"[^>]*>\s*([\d,]+)\s*</a>",
    re.DOTALL,
)


def _fetch(url: str, timeout: int = 30) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-CA,en;q=0.9",
        },
    )
    ctx = ssl.create_default_context()
    with urlopen(request, timeout=timeout, context=ctx) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_subject_labels(page_html: str) -> dict[int, str]:
    """Return {ocl_code: label} parsed from a regSms HTML page.

    Deduplicates by `ocl_code` since trend tables repeat the same row.
    """
    labels: dict[int, str] = {}
    for label, code in _SUBJECT_ROW_RE.findall(page_html):
        code_int = int(code)
        if code_int in labels:
            continue
        # Unescape HTML entities (e.g. &#039; → ').
        labels[code_int] = html.unescape(label.strip())
    return labels


def parse_communication_counts(page_html: str) -> dict[int, int]:
    """Sum communication counts per OCL code across every period visible in cmmLgSms.

    The page exposes the most recent reporting period plus the last six
    completed periods (≈ 6–7 months of data). We sum each (cid, dt) pair once
    — the current month appears in both tables but must be counted only once —
    so the resulting figure approximates the recent-activity baseline that the
    EPAC-2149 mapping completeness report calls for.
    """
    seen: dict[tuple[int, str], int] = {}
    for match in _COMM_CELL_RE.finditer(page_html):
        query = match.group("query")
        count_str = match.group(2)
        cid_match = re.search(r"cid=(\d+)", query)
        dt_match = re.search(r"dt=(\d{4}-\d{2})", query)
        if not cid_match or not dt_match:
            continue
        key = (int(cid_match.group(1)), dt_match.group(1))
        if key in seen:
            continue
        seen[key] = int(count_str.replace(",", ""))

    counts: dict[int, int] = {}
    for (code, _dt), value in seen.items():
        counts[code] = counts.get(code, 0) + value
    return counts


def merge_bilingual(
    en_labels: dict[int, str], fr_labels: dict[int, str]
) -> list[OCLSubjectMatter]:
    """Join the English and French label dictionaries by `ocl_code`.

    A code that is missing a French label is still returned (label_fr empty);
    the ingest should not silently drop a code just because the FR view is out
    of sync. The reverse case (FR-only) is treated the same way — we surface
    every code we saw in either view so future audits can spot drift.
    """
    codes = sorted(set(en_labels) | set(fr_labels))
    return [
        OCLSubjectMatter(
            ocl_code=code,
            label_en=en_labels.get(code, ""),
            label_fr=fr_labels.get(code, ""),
            active=True,
        )
        for code in codes
    ]


def fetch_subject_matters() -> list[OCLSubjectMatter]:
    en_html = _fetch(f"{BASE_URL}{REG_SUBJECTS_PATH}?lang=eng")
    fr_html = _fetch(f"{BASE_URL}{REG_SUBJECTS_PATH}?lang=fra")
    return merge_bilingual(
        parse_subject_labels(en_html),
        parse_subject_labels(fr_html),
    )


def build_mapping_report(
    subjects: list[OCLSubjectMatter],
    comm_counts: dict[int, int],
    mapping: dict[int, str],
    as_of: str,
) -> str:
    """Render the markdown mapping-completeness report.

    Each row pairs an OCL code with its recent communications-count snapshot
    and `mapped` / `unmapped` status. `mapping` is a `ocl_code → epac_topic`
    dict. EPAC-2150 already shipped a mapping at
    `backend/lobbying/ocl_topic_map.json`, but it is keyed by synthetic
    `SMT-N` strings rather than the integer OCL codes the live registry uses;
    until that key format is reconciled the script passes an empty mapping in,
    so every code surfaces as `unmapped` and the report doubles as a checklist
    of codes that still need an EPAC topic assignment.
    """
    total = len(subjects)
    mapped_count = sum(1 for s in subjects if s.ocl_code in mapping)
    unmapped_count = total - mapped_count
    # Show highest-volume codes first so reviewers can triage by impact.
    ordered = sorted(
        subjects,
        key=lambda s: (-comm_counts.get(s.ocl_code, 0), s.ocl_code),
    )

    lines = [
        "# OCL subject-matter mapping completeness",
        "",
        f"_As of {as_of}. Source: {BASE_URL}{COMM_SUBJECTS_PATH}._",
        "",
        "Lists every OCL subject-matter code seen in monthly communication reports",
        "over the most recent reporting periods published by the Office of the",
        "Commissioner of Lobbying (the current month plus the six prior periods —",
        "≈ 6–7 months of activity, as much as the OCL public dashboard surfaces",
        "without ingesting the full open-data CSV). Each row is flagged",
        "`mapped` or `unmapped` against the EPAC monitored-topic mapping.",
        "EPAC-2150 already shipped `backend/lobbying/ocl_topic_map.json`, but it",
        "keys mappings by synthetic `SMT-N` strings rather than the integer OCL",
        "codes the live registry uses; until that key format is reconciled the",
        "report carries an empty mapping and every code surfaces as `unmapped`,",
        "doubling as a backlog of codes that still need an EPAC topic",
        "assignment.",
        "",
        f"- Total active OCL codes: **{total}**",
        f"- Mapped to EPAC topics: **{mapped_count}**",
        f"- Unmapped: **{unmapped_count}**",
        "",
        "| OCL code | Label (EN) | Communications (recent periods) | Status | EPAC topic |",
        "|---:|---|---:|---|---|",
    ]
    for subject in ordered:
        count = comm_counts.get(subject.ocl_code, 0)
        status = "mapped" if subject.ocl_code in mapping else "unmapped"
        topic = mapping.get(subject.ocl_code, "—")
        lines.append(
            f"| {subject.ocl_code} | {subject.label_en} | {count:,} | {status} | {topic} |"
        )
    lines.append("")
    return "\n".join(lines)


def _resolve_report_path(explicit: Optional[str]) -> Path:
    if explicit:
        return Path(explicit)
    # The script lives under backend/lobbying/; the report sits next to it.
    return Path(__file__).resolve().parent / "mapping_report.md"


def _emit_report(
    subjects: list[OCLSubjectMatter], output_path: Path
) -> int:
    """Fetch recent communication counts and write the markdown report."""
    try:
        comm_html = _fetch(f"{BASE_URL}{COMM_SUBJECTS_PATH}?lang=eng")
    except (HTTPError, URLError) as exc:
        logger.error(
            "fetch failed for cmmLgSms",
            extra={"error": f"{type(exc).__name__}: {exc}"},
        )
        return 4

    comm_counts = parse_communication_counts(comm_html)
    if not comm_counts:
        logger.error(
            "parsed zero communication counts — cmmLgSms markup may have changed",
            extra={"error": "ParseError: zero counts"},
        )
        return 5

    as_of = datetime.now(tz=timezone.utc).date().isoformat()
    # Sub-issue B will introduce ocl_to_epac_topic mapping; until then the
    # report intentionally surfaces every code as unmapped.
    report = build_mapping_report(subjects, comm_counts, mapping={}, as_of=as_of)
    output_path.write_text(report, encoding="utf-8")
    logger.info(
        "mapping report written",
        extra={"output": str(output_path), "codes_with_counts": len(comm_counts)},
    )
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        action="store_true",
        help="Also refresh backend/lobbying/mapping_report.md from cmmLgSms.",
    )
    parser.add_argument(
        "--report-output",
        default=None,
        help="Override the report destination (defaults to mapping_report.md beside this script).",
    )
    args = parser.parse_args(argv)

    started_at = time.monotonic()
    logger.info("pipeline started", extra={"refresh_report": args.report})

    try:
        subjects = fetch_subject_matters()
    except (HTTPError, URLError) as exc:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        logger.error(
            "fetch failed for regSms",
            extra={
                "error": f"{type(exc).__name__}: {exc}",
                "duration_ms": duration_ms,
            },
        )
        return 2

    if not subjects:
        duration_ms = int((time.monotonic() - started_at) * 1000)
        logger.error(
            "parsed zero subject matters — regSms markup may have changed",
            extra={"error": "ParseError: zero subject matters", "duration_ms": duration_ms},
        )
        return 3

    sys.stdout.write(
        json.dumps([asdict(s) for s in subjects], indent=2, ensure_ascii=False) + "\n"
    )

    if args.report:
        report_path = _resolve_report_path(args.report_output)
        exit_code = _emit_report(subjects, report_path)
        if exit_code != 0:
            return exit_code

    duration_ms = int((time.monotonic() - started_at) * 1000)
    logger.info(
        "pipeline finished",
        extra={"records_processed": len(subjects), "duration_ms": duration_ms},
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
