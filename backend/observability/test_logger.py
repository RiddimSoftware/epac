"""Unit tests for backend.observability.logger."""

from __future__ import annotations

import io
import json
import logging
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from logger import JsonFormatter, get_logger


def make_record(
    name: str = "pipeline_x",
    level: int = logging.INFO,
    msg: str = "hello",
    exc_info: object | None = None,
    extra: dict | None = None,
) -> logging.LogRecord:
    record = logging.LogRecord(
        name=name,
        level=level,
        pathname=__file__,
        lineno=1,
        msg=msg,
        args=(),
        exc_info=exc_info,
    )
    if extra:
        for key, value in extra.items():
            setattr(record, key, value)
    return record


class JsonFormatterTests(unittest.TestCase):
    def test_emits_json_with_required_fields(self) -> None:
        record = make_record()
        payload = json.loads(JsonFormatter().format(record))
        self.assertIn("timestamp", payload)
        self.assertEqual(payload["level"], "INFO")
        self.assertEqual(payload["pipeline"], "pipeline_x")
        self.assertEqual(payload["message"], "hello")

    def test_timestamp_is_iso8601_utc(self) -> None:
        record = make_record()
        payload = json.loads(JsonFormatter().format(record))
        self.assertTrue(payload["timestamp"].endswith("Z"),
                         f"Expected UTC suffix Z, got {payload['timestamp']}")

    def test_extra_fields_merge_into_payload(self) -> None:
        record = make_record(extra={"records_processed": 47, "duration_ms": 2341})
        payload = json.loads(JsonFormatter().format(record))
        self.assertEqual(payload["records_processed"], 47)
        self.assertEqual(payload["duration_ms"], 2341)

    def test_stdlib_fields_are_stripped(self) -> None:
        record = make_record()
        payload = json.loads(JsonFormatter().format(record))
        self.assertNotIn("pathname", payload)
        self.assertNotIn("lineno", payload)
        self.assertNotIn("module", payload)

    def test_exception_is_serialized(self) -> None:
        try:
            raise ValueError("boom")
        except ValueError:
            import sys
            record = make_record(level=logging.ERROR, msg="failed", exc_info=sys.exc_info())
        payload = json.loads(JsonFormatter().format(record))
        self.assertEqual(payload["level"], "ERROR")
        self.assertIn("error", payload)
        self.assertIn("ValueError", payload["error"])
        self.assertIn("boom", payload["error"])


class GetLoggerTests(unittest.TestCase):
    def setUp(self) -> None:
        # Reset any logger state between tests so configuration is fresh.
        for name in list(logging.root.manager.loggerDict.keys()):
            if name.startswith("test_pipeline"):
                logger = logging.getLogger(name)
                logger.handlers.clear()
                if hasattr(logger, "_epac_configured"):
                    delattr(logger, "_epac_configured")

    def test_idempotent_configuration(self) -> None:
        first = get_logger("test_pipeline_idempotent")
        second = get_logger("test_pipeline_idempotent")
        self.assertIs(first, second)
        self.assertEqual(len(first.handlers), 1)  # stdout only, no file

    def test_writes_json_to_stdout(self) -> None:
        logger = get_logger("test_pipeline_stdout")
        # Replace the stdout stream with a StringIO so we can read what was
        # emitted without depending on captured-stdout fixtures.
        sink = io.StringIO()
        for handler in logger.handlers:
            if isinstance(handler, logging.StreamHandler):
                handler.stream = sink
        logger.info("hello", extra={"records_processed": 10})
        line = sink.getvalue().strip()
        payload = json.loads(line)
        self.assertEqual(payload["pipeline"], "test_pipeline_stdout")
        self.assertEqual(payload["message"], "hello")
        self.assertEqual(payload["records_processed"], 10)

    def test_file_handler_attached_when_log_dir_set(self) -> None:
        with TemporaryDirectory() as tmpdir:
            logger = get_logger("test_pipeline_file", log_dir=tmpdir)
            # Stream + rotating file = 2 handlers.
            self.assertEqual(len(logger.handlers), 2)
            logger.info("written-to-file")
            for handler in logger.handlers:
                handler.flush()
            log_path = Path(tmpdir) / "test_pipeline_file.log"
            self.assertTrue(log_path.exists())
            content = log_path.read_text(encoding="utf-8").strip()
            payload = json.loads(content)
            self.assertEqual(payload["message"], "written-to-file")


if __name__ == "__main__":
    unittest.main()
