#!/usr/bin/env python3
"""Plan native GitHub Actions indexer runs.

The dry-run mode is the CI-verifiable contract for the future native indexer
workflows: it crosses the CLI composition root and emits the payload shape that
the workflows can summarize without requiring AWS credentials or live data.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


HANSARD_MANIFEST_FORMAT = {
    "version": "string",
    "built_at": "rfc3339",
    "parliament_number": "integer",
    "session_number": "integer",
    "sitting_count": "integer",
    "intervention_count": "integer",
    "message_count": "integer",
    "sqlite_key": "string",
    "sqlite_size_bytes": "integer",
    "sqlite_sha256": "sha256",
}

LOBBYING_MANIFEST_FORMAT = {
    "version": "string",
    "built_at": "rfc3339",
    "sqlite_key": "string",
    "sqlite_size_bytes": "integer",
    "sqlite_sha256": "sha256",
    "table_counts": "object[string,integer]",
}

BILLS_MANIFEST_FORMAT = {
    "version": "string",
    "built_at": "rfc3339",
    "parliament_number": "integer",
    "session_number": "integer",
    "sqlite_key": "string",
    "sqlite_size_bytes": "integer",
    "sqlite_sha256": "sha256",
    "table_counts": "object[string,integer]",
}

MEMBERS_MANIFEST_FORMAT = {
    "version": "string",
    "built_at": "rfc3339",
    "sqlite_key": "string",
    "sqlite_size_bytes": "integer",
    "sqlite_sha256": "sha256",
    "table_counts": "object[string,integer]",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run or plan native GitHub Actions indexer execution."
    )
    parser.add_argument(
        "pipeline",
        choices=(
            "hansard-search-index",
            "lobbying-index",
            "bills-indexer",
            "members-indexer",
        ),
        help="Indexer pipeline to run.",
    )
    parser.add_argument(
        "--environment",
        choices=("staging", "production"),
        required=True,
        help="Deployment environment targeted by the reindex.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Emit the planned native indexer contract without running the indexer.",
    )
    parser.add_argument(
        "--format",
        choices=("json",),
        default="json",
        help="Output format for the CLI payload.",
    )
    parser.add_argument(
        "--parliament-number",
        type=int,
        default=45,
        help="Hansard parliament number override.",
    )
    parser.add_argument(
        "--session-number",
        type=int,
        default=1,
        help="Hansard session number override.",
    )
    return parser


def planned_payload(args: argparse.Namespace, summary_path: Path | None) -> dict[str, Any]:
    if args.pipeline == "hansard-search-index":
        return {
            "pipeline": args.pipeline,
            "environment": args.environment,
            "mode": "dry-run",
            "status": "planned",
            "summary_markdown_path": str(summary_path) if summary_path else None,
            "manifest_format": HANSARD_MANIFEST_FORMAT,
            "parameters": {
                "parliament_number": args.parliament_number,
                "session_number": args.session_number,
            },
            "commands": [
                {
                    "working_directory": "backend/hansard-search-index",
                    "argv": ["go", "run", "."],
                    "env": {
                        "PARLIAMENT_NUMBER": str(args.parliament_number),
                        "SESSION_NUMBER": str(args.session_number),
                    },
                }
            ],
        }

    if args.pipeline == "lobbying-index":
        return {
            "pipeline": args.pipeline,
            "environment": args.environment,
            "mode": "dry-run",
            "status": "planned",
            "summary_markdown_path": str(summary_path) if summary_path else None,
            "manifest_format": LOBBYING_MANIFEST_FORMAT,
            "parameters": {
                "phase": "all",
            },
            "commands": [
                {
                    "working_directory": "backend/lobbying-index",
                    "argv": ["go", "run", "."],
                    "env": {
                        "PHASE": "all",
                    },
                }
            ],
        }

    if args.pipeline == "bills-indexer":
        return {
            "pipeline": args.pipeline,
            "environment": args.environment,
            "mode": "dry-run",
            "status": "planned",
            "summary_markdown_path": str(summary_path) if summary_path else None,
            "manifest_format": BILLS_MANIFEST_FORMAT,
            "parameters": {
                "parliament_number": args.parliament_number,
                "session_number": args.session_number,
            },
            "commands": [
                {
                    "working_directory": "backend/bills-indexer",
                    "argv": ["go", "run", "."],
                    "env": {
                        "PARLIAMENT_NUMBER": str(args.parliament_number),
                        "SESSION_NUMBER": str(args.session_number),
                    },
                }
            ],
        }

    return {
        "pipeline": args.pipeline,
        "environment": args.environment,
        "mode": "dry-run",
        "status": "planned",
        "summary_markdown_path": str(summary_path) if summary_path else None,
        "manifest_format": MEMBERS_MANIFEST_FORMAT,
        "parameters": {},
        "commands": [
            {
                "working_directory": "backend/members-indexer",
                "argv": ["go", "run", "."],
                "env": {},
            }
        ],
    }


def write_summary(path: Path | None, payload: dict[str, Any]) -> None:
    if path is None:
        return

    rows = [
        f"## {payload['pipeline']} native reindex",
        "",
        f"- Environment: `{payload['environment']}`",
        f"- Mode: `{payload['mode']}`",
        f"- Status: `{payload['status']}`",
        "",
        "| Output | Format |",
        "|---|---|",
    ]
    for field_name, field_type in payload["manifest_format"].items():
        rows.append(f"| manifest.{field_name} | {field_type} |")
    rows.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as summary:
        summary.write("\n".join(rows) + "\n")


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.dry_run:
        print(
            "non-dry-run native indexer execution is not implemented yet",
            file=sys.stderr,
        )
        return 2

    summary_raw = os.environ.get("GITHUB_STEP_SUMMARY", "").strip()
    summary_path = Path(summary_raw) if summary_raw else None
    payload = planned_payload(args, summary_path)
    write_summary(summary_path, payload)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
