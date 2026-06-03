#!/usr/bin/env python3
"""Precompute MP lobbying party and national cohort averages.

The OCL ingestion layer owns raw Commissioner of Lobbying data and should run
this job after each quarterly ingest. This module keeps the application policy
pure: the `CompareMPLobbyingToCohort` use case depends on a repository port,
while `PostgresCohortStatisticsRepository` is the database adapter.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Iterable, Optional, Protocol, Sequence


PIPELINE_NAME = "lobbying-cohort-averages"
DEFAULT_SOURCE_TABLE = "lobbying_member_communication_totals"
MIN_PARTY_MEMBER_COUNT = 5
NATIONAL_PARTY_KEY: Optional[str] = None


class _JSONFormatter(logging.Formatter):
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


@dataclass(frozen=True)
class ParliamentMember:
    member_id: str
    party: str


@dataclass(frozen=True)
class MemberCommunicationTotal:
    parliament: int
    member_id: str
    total_communications: int


@dataclass(frozen=True)
class CohortAverage:
    parliament: int
    party: Optional[str]
    avg_communications: Optional[Decimal]
    computed_at: datetime


@dataclass(frozen=True)
class CohortComparison:
    mp_total: int
    party_avg: Optional[Decimal]
    national_avg: Optional[Decimal]
    ratio_vs_party: Optional[Decimal]
    ratio_vs_national: Optional[Decimal]

    def as_response_row(self) -> dict[str, Any]:
        return {
            "mp_total": self.mp_total,
            "party_avg": decimal_or_none(self.party_avg),
            "national_avg": decimal_or_none(self.national_avg),
            "ratio_vs_party": decimal_or_none(self.ratio_vs_party),
            "ratio_vs_national": decimal_or_none(self.ratio_vs_national),
        }


class CohortStatisticsRepository(Protocol):
    def list_current_members(self) -> Sequence[ParliamentMember]:
        ...

    def list_member_communication_totals(self, parliament: Optional[int] = None) -> Sequence[MemberCommunicationTotal]:
        ...

    def replace_cohort_averages(
        self,
        averages: Sequence[CohortAverage],
        parliaments: Optional[Sequence[int]] = None,
    ) -> None:
        ...

    def member_total(self, parliament: int, member_id: str) -> int:
        ...

    def member_party(self, member_id: str) -> Optional[str]:
        ...

    def cohort_average(self, parliament: int, party: Optional[str]) -> Optional[Decimal]:
        ...


def precompute_cohort_averages(
    repo: CohortStatisticsRepository,
    *,
    parliament: Optional[int] = None,
    computed_at: Optional[datetime] = None,
) -> list[CohortAverage]:
    computed_at = computed_at or datetime.now(timezone.utc)
    members = [m for m in repo.list_current_members() if m.member_id and m.party]
    party_by_member = {m.member_id: m.party for m in members}
    known_parties = sorted({m.party for m in members})

    totals = [
        t for t in repo.list_member_communication_totals(parliament)
        if t.total_communications > 0 and t.member_id in party_by_member
    ]
    totals_by_parliament: dict[int, list[MemberCommunicationTotal]] = {}
    for total in totals:
        totals_by_parliament.setdefault(total.parliament, []).append(total)

    averages: list[CohortAverage] = []
    for parl in sorted(totals_by_parliament):
        parliament_totals = totals_by_parliament[parl]
        averages.append(CohortAverage(
            parliament=parl,
            party=NATIONAL_PARTY_KEY,
            avg_communications=mean_decimal(t.total_communications for t in parliament_totals),
            computed_at=computed_at,
        ))

        totals_by_party: dict[str, list[int]] = {party: [] for party in known_parties}
        for total in parliament_totals:
            totals_by_party.setdefault(party_by_member[total.member_id], []).append(total.total_communications)

        for party in sorted(totals_by_party):
            party_totals = totals_by_party[party]
            averages.append(CohortAverage(
                parliament=parl,
                party=party,
                avg_communications=(
                    mean_decimal(party_totals)
                    if len(party_totals) >= MIN_PARTY_MEMBER_COUNT
                    else None
                ),
                computed_at=computed_at,
            ))

    target_parliaments = [parliament] if parliament is not None else sorted(totals_by_parliament)
    repo.replace_cohort_averages(averages, parliaments=target_parliaments)
    return averages


def compare_mp_lobbying_to_cohort(
    repo: CohortStatisticsRepository,
    *,
    parliament: int,
    member_id: str,
) -> CohortComparison:
    party = repo.member_party(member_id)
    mp_total = repo.member_total(parliament, member_id)
    party_avg = repo.cohort_average(parliament, party) if party else None
    national_avg = repo.cohort_average(parliament, NATIONAL_PARTY_KEY)
    return build_comparison_row(mp_total=mp_total, party_avg=party_avg, national_avg=national_avg)


def build_comparison_row(
    *,
    mp_total: int,
    party_avg: Optional[Decimal],
    national_avg: Optional[Decimal],
) -> CohortComparison:
    return CohortComparison(
        mp_total=mp_total,
        party_avg=party_avg,
        national_avg=national_avg,
        ratio_vs_party=ratio(mp_total, party_avg),
        ratio_vs_national=ratio(mp_total, national_avg),
    )


def mean_decimal(values: Iterable[int]) -> Decimal:
    numbers = [Decimal(value) for value in values]
    if not numbers:
        return Decimal("0")
    return sum(numbers) / Decimal(len(numbers))


def ratio(numerator: int, denominator: Optional[Decimal]) -> Optional[Decimal]:
    if denominator is None or denominator == 0:
        return None
    return Decimal(numerator) / denominator


def decimal_or_none(value: Optional[Decimal]) -> Optional[float]:
    if value is None:
        return None
    return float(value)


class PostgresCohortStatisticsRepository:
    def __init__(self, database_url: str, *, source_table: str = DEFAULT_SOURCE_TABLE) -> None:
        if not database_url.strip():
            raise ValueError("DATABASE_URL is required")
        self.database_url = database_url
        self.source_table = quote_identifier(source_table)
        try:
            import psycopg  # type: ignore
        except ImportError as exc:
            raise RuntimeError("psycopg is required to run the lobbying cohort precompute job") from exc
        self._psycopg = psycopg

    def list_current_members(self) -> Sequence[ParliamentMember]:
        with self._connect() as conn:
            rows = conn.execute("""
                SELECT person_id::text, caucus::text
                FROM members
                WHERE person_id IS NOT NULL
                  AND person_id <> ''
                  AND caucus IS NOT NULL
                  AND caucus <> ''
                  AND to_date IS NULL
            """).fetchall()
        return [ParliamentMember(member_id=row[0], party=row[1]) for row in rows]

    def list_member_communication_totals(self, parliament: Optional[int] = None) -> Sequence[MemberCommunicationTotal]:
        where = ""
        params: tuple[Any, ...] = ()
        if parliament is not None:
            where = "WHERE parliament = %s"
            params = (parliament,)
        query = f"""
            SELECT parliament::int, member_id::text, SUM(total_communications)::int
            FROM {self.source_table}
            {where}
            GROUP BY parliament, member_id
        """
        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()
        return [
            MemberCommunicationTotal(parliament=row[0], member_id=row[1], total_communications=row[2])
            for row in rows
        ]

    def replace_cohort_averages(
        self,
        averages: Sequence[CohortAverage],
        parliaments: Optional[Sequence[int]] = None,
    ) -> None:
        target_parliaments = sorted(set(parliaments or [average.parliament for average in averages]))
        with self._connect() as conn:
            with conn.transaction():
                if target_parliaments:
                    conn.execute("DELETE FROM lobbying_cohort_averages WHERE parliament = ANY(%s)", (target_parliaments,))
                for average in averages:
                    conn.execute("""
                        INSERT INTO lobbying_cohort_averages
                            (parliament, party, avg_communications, computed_at)
                        VALUES (%s, %s, %s, %s)
                    """, (
                        average.parliament,
                        average.party,
                        average.avg_communications,
                        average.computed_at,
                    ))

    def member_total(self, parliament: int, member_id: str) -> int:
        query = f"""
            SELECT COALESCE(SUM(total_communications), 0)::int
            FROM {self.source_table}
            WHERE parliament = %s AND member_id::text = %s
        """
        with self._connect() as conn:
            return int(conn.execute(query, (parliament, member_id)).fetchone()[0])

    def member_party(self, member_id: str) -> Optional[str]:
        with self._connect() as conn:
            row = conn.execute("""
                SELECT caucus::text
                FROM members
                WHERE person_id::text = %s
                ORDER BY CASE WHEN to_date IS NULL THEN 0 ELSE 1 END
                LIMIT 1
            """, (member_id,)).fetchone()
        return row[0] if row else None

    def cohort_average(self, parliament: int, party: Optional[str]) -> Optional[Decimal]:
        if party is None:
            query = """
                SELECT avg_communications
                FROM lobbying_cohort_averages
                WHERE parliament = %s AND party IS NULL
            """
            params: tuple[Any, ...] = (parliament,)
        else:
            query = """
                SELECT avg_communications
                FROM lobbying_cohort_averages
                WHERE parliament = %s AND party = %s
            """
            params = (parliament, party)
        with self._connect() as conn:
            row = conn.execute(query, params).fetchone()
        return row[0] if row else None

    def record_health(self, record_count: int, run_error: Optional[BaseException]) -> None:
        now = datetime.now(timezone.utc)
        error_message = str(run_error) if run_error else None
        success_at = now if run_error is None else None
        with self._connect() as conn:
            conn.execute("""
                INSERT INTO pipeline_health
                    (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
                VALUES (%s, %s, %s, %s, %s, 2208)
                ON CONFLICT (name) DO UPDATE SET
                    last_run_at = EXCLUDED.last_run_at,
                    last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
                    last_error = EXCLUDED.last_error,
                    record_count = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
            """, (PIPELINE_NAME, now, success_at, error_message, record_count if run_error is None else None))

    def _connect(self) -> Any:
        return self._psycopg.connect(self.database_url)


def quote_identifier(identifier: str) -> str:
    parts = identifier.split(".")
    if not parts or any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", part) for part in parts):
        raise ValueError(f"unsafe SQL identifier: {identifier!r}")
    return ".".join(f'"{part}"' for part in parts)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Precompute lobbying cohort averages")
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL", ""))
    parser.add_argument("--source-table", default=os.getenv("LOBBYING_MEMBER_TOTALS_TABLE", DEFAULT_SOURCE_TABLE))
    parser.add_argument("--parliament", type=int, default=None)
    args = parser.parse_args(argv)

    repo = PostgresCohortStatisticsRepository(args.database_url, source_table=args.source_table)
    try:
        averages = precompute_cohort_averages(repo, parliament=args.parliament)
    except Exception as exc:
        repo.record_health(0, exc)
        logger.error("pipeline failed", extra={"error": str(exc)})
        return 1

    repo.record_health(len(averages), None)
    logger.info("pipeline finished", extra={"records_processed": len(averages), "parliament": args.parliament})
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
