"""Structured JSON logging for the epac Python backend.

Each log record is emitted as a single JSON object on stdout (and optionally
into a rotating file under `logs/<pipeline>.log`). The formatter is
hand-rolled rather than using `python-json-logger` so the backend has zero
runtime dependencies for logging — important for the lightweight Lambda /
container deploys these pipelines run inside.

Usage:

    from backend.observability.logger import get_logger

    logger = get_logger("hansard_sync")
    logger.info("pipeline.start")
    try:
        ...
        logger.info("pipeline.done", extra={"records_processed": 47, "duration_ms": 2341})
    except Exception:
        logger.exception("pipeline.failed", extra={"url": url})

Every record carries `timestamp`, `level`, `pipeline`, and `message`.
Anything passed via `extra={...}` is merged into the JSON object — the
pipeline-specific fields documented on EPAC-176 (records_processed,
duration_ms, error, url, etc.) flow through this mechanism.
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# Stdlib's LogRecord adds a static set of fields automatically. We strip those
# from `extra` to keep the JSON output tight and predictable.
_STDLIB_FIELDS = frozenset({
    "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
    "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
    "created", "msecs", "relativeCreated", "thread", "threadName",
    "processName", "process", "asctime", "taskName",
})


class JsonFormatter(logging.Formatter):
    """One JSON object per record, ISO-8601 UTC timestamp, structured extras."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc)
                .isoformat(timespec="milliseconds")
                .replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["error"] = self.formatException(record.exc_info)
        for key, value in record.__dict__.items():
            if key in _STDLIB_FIELDS or key.startswith("_") or key == "message":
                continue
            payload[key] = value
        return json.dumps(payload, ensure_ascii=False, default=str)


def get_logger(
    pipeline: str,
    level: int = logging.INFO,
    log_dir: str | os.PathLike[str] | None = None,
    rotation_days: int = 7,
) -> logging.Logger:
    """Return a logger for `pipeline`, configured idempotently.

    Calling this twice for the same pipeline returns the same logger without
    re-attaching handlers — important because pipelines are typically invoked
    multiple times per process (CLI, then in tests, etc.).

    `log_dir` defaults to `$EPAC_LOG_DIR` if set, else falls back to
    stdout-only (no file rotation). Production deploys set the env var; local
    dev runs see the JSON on stdout where it's easy to grep.
    """
    logger = logging.getLogger(pipeline)
    if getattr(logger, "_epac_configured", False):
        return logger

    logger.setLevel(level)
    logger.propagate = False

    formatter = JsonFormatter()

    stream_handler = logging.StreamHandler(stream=sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    resolved_dir = log_dir or os.environ.get("EPAC_LOG_DIR")
    if resolved_dir:
        log_path = Path(resolved_dir)
        log_path.mkdir(parents=True, exist_ok=True)
        # Rotate at midnight, keep `rotation_days` files. Rotated files are
        # gzipped via the `.gz` namer so disk usage stays bounded.
        file_handler = logging.handlers.TimedRotatingFileHandler(
            filename=str(log_path / f"{pipeline}.log"),
            when="midnight",
            backupCount=rotation_days,
            utc=True,
            encoding="utf-8",
        )
        file_handler.namer = lambda name: f"{name}.gz"
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    setattr(logger, "_epac_configured", True)
    return logger
