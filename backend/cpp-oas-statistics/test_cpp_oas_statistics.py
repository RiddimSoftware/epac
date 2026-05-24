"""Unit tests for cpp_oas_statistics.py."""

from __future__ import annotations

import io
import hashlib
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

import cpp_oas_statistics

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


class FakeS3Client:
    def __init__(self) -> None:
        self.calls = []

    def put_object(self, **kwargs) -> None:
        self.calls.append(kwargs)


def _load_fixture(name: str) -> bytes:
    with open(os.path.join(FIXTURES_DIR, name), "rb") as f:
        return f.read()


class ParsePeriodTests(unittest.TestCase):
    def test_standard_bilingual_format(self) -> None:
        self.assertEqual(cpp_oas_statistics.parse_period("Jan. / jan. 2023"), (2023, 1))

    def test_returns_none_for_empty(self) -> None:
        self.assertIsNone(cpp_oas_statistics.parse_period(""))

    def test_returns_none_for_unparseable(self) -> None:
        self.assertIsNone(cpp_oas_statistics.parse_period("Total / Total"))


class CppOasStatisticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cpp_csv = _load_fixture("cpp_fixture.csv")
        self.oas_csv = _load_fixture("oas_fixture.csv")

    def test_parses_happy_path_fixture(self) -> None:
        payload = cpp_oas_statistics.build_payload(self.cpp_csv, self.oas_csv)

        self.assertIn("provinces", payload)
        self.assertIn("national", payload)
        self.assertIn("history_years", payload)
        self.assertEqual(len(payload["provinces"]), 13)
        self.assertEqual(payload["history_years"], [2022, 2023, 2024])

        ontario = next(p for p in payload["provinces"] if p["province_code"] == "ON")
        self.assertEqual(ontario["province"], "Ontario")
        self.assertEqual(ontario["cpp_retirement_recipients"], 1020000)
        self.assertEqual(ontario["cpp_reference_period"], "2024-01")
        self.assertEqual(ontario["oas_pension_recipients"], 920000)
        self.assertEqual(ontario["oas_reference_period"], "2024-01")
        self.assertEqual(len(ontario["history"]), 3)

        national = payload["national"]
        self.assertEqual(national["cpp_retirement_recipients"], 1530000)
        self.assertEqual(national["oas_pension_recipients"], 1330000)
        self.assertEqual(national["cpp_reference_period"], "2024-01")
        self.assertEqual(national["oas_reference_period"], "2024-01")

        with open(os.path.join(FIXTURES_DIR, "expected_output.json"), encoding="utf-8") as f:
            expected = json.load(f)
        actual = {k: v for k, v in payload.items() if k != "generated_at"}
        self.assertEqual(actual, expected)

    def test_handles_missing_required_field(self) -> None:
        # CSV with no "Retirement" column — all rows skipped → ValueError, not silent KeyError
        bad_cpp = b"Period,Province,NotARecognisedColumn\nJan. / jan. 2024,ONTARIO,1000000\n"
        with self.assertRaises(ValueError):
            cpp_oas_statistics.build_payload(bad_cpp, self.oas_csv)

    def test_handles_malformed_upstream(self) -> None:
        # Truncated / empty bytes → no parseable rows → ValueError raised before
        # "pipeline finished" can be logged.
        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            with patch("cpp_oas_statistics.fetch_csv", side_effect=[b"", b""]):
                with self.assertRaises(ValueError):
                    cpp_oas_statistics.main([])
        self.assertNotIn("pipeline finished", stderr_buf.getvalue())

    def test_emits_required_log_events(self) -> None:
        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            with patch(
                "cpp_oas_statistics.fetch_csv",
                side_effect=[self.cpp_csv, self.oas_csv],
            ):
                with tempfile.TemporaryDirectory() as tmpdir:
                    out_file = os.path.join(tmpdir, "out.json")
                    result = cpp_oas_statistics.main(["--output", out_file])
        self.assertEqual(result, 0)

        log_lines = [l for l in stderr_buf.getvalue().splitlines() if l.strip()]
        self.assertTrue(log_lines, "No log output captured on stderr")
        log_events = [json.loads(line) for line in log_lines]
        messages = [e["message"] for e in log_events]
        self.assertIn("pipeline started", messages)
        self.assertIn("pipeline finished", messages)

        finished = next(e for e in log_events if e["message"] == "pipeline finished")
        self.assertIn("records_processed", finished)
        self.assertIn("duration_ms", finished)
        self.assertEqual(finished["pipeline"], "cpp-oas-statistics")

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self) -> None:
        payload = cpp_oas_statistics.build_payload(self.cpp_csv, self.oas_csv)
        s3_client = FakeS3Client()

        published = cpp_oas_statistics.publish_payload(
            payload,
            bucket="artifact-bucket",
            s3_client=s3_client,
        )

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/cpp-oas-statistics/all.json")
        self.assertIn("statistics/v1/cpp-oas-statistics/national.json", keys)
        self.assertIn("statistics/v1/cpp-oas-statistics/province-on.json", keys)
        call = s3_client.calls[0]
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
