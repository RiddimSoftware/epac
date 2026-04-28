# Backend logging convention

The Python backend logs as one JSON object per record. No `print()` —
use `get_logger("<pipeline-name>")` from `backend.observability.logger`.

## Quick start

```python
from backend.observability.logger import get_logger

logger = get_logger("hansard_sync")

logger.info("pipeline.start")
try:
    records = run_pipeline()
    logger.info("pipeline.done", extra={
        "records_processed": len(records),
        "duration_ms": elapsed_ms,
    })
except Exception:
    logger.exception("pipeline.failed", extra={"url": url})
```

## Conventions

- **Pipeline name** = the logger name. One pipeline per logger; pass it
  to `get_logger(...)` so all records carry it as the `pipeline` field.
- **Message** is dotted, machine-grep-friendly (`pipeline.start`,
  `pipeline.done`, `pipeline.failed`, `fetch.http_error`, ...). Avoid
  punctuation — make it easy to alert on `level=ERROR AND message="*.failed"`.
- **Structured data** goes in `extra={...}` — `records_processed`,
  `duration_ms`, `url`, `status_code`, `error`, `pipeline_specific_field`.
  These merge into the JSON object directly.
- **Exceptions** use `logger.exception(...)` (not `logger.error`) so the
  formatter captures the full stack trace under the `error` field.
- **Levels**: `INFO` for happy path, `WARNING` for recoverable network
  blips, `ERROR` for handled failures, `CRITICAL` only for "the pipeline
  is not running at all." Anything ≥ `WARNING` should pull a human in.

## Where logs go

- **Stdout** always (production deploys ship stdout to CloudWatch /
  Logtail; local dev sees them on the console).
- **File** when the `EPAC_LOG_DIR` env var is set — rotated nightly,
  7 days retained, gzipped. Useful for cron-like runs that don't have
  a stdout collector.

## Adding a new pipeline

1. Pick a stable, hyphen-free name — `hansard_sync`, `votes_sync`,
   `cabinet_ingest`. This becomes the JSON `pipeline` field and the
   rotated-file basename.
2. `logger = get_logger("<name>")` at module scope.
3. Log `pipeline.start` and `pipeline.done` from `main()`. Wrap the
   work in a `try`/`except` and `logger.exception("pipeline.failed")`
   on the unhandled-error path.

The factory is idempotent — calling `get_logger(<name>)` twice returns
the same logger without re-attaching handlers, so import-time
configuration plays nicely with tests.
