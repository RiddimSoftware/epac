#!/usr/bin/env python3
"""Tests for submit_beta_app_review.py with mocked ASC API calls."""

import io
import json
import sys
import types
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parent / "submit_beta_app_review.py"


class FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = json.dumps(self._payload)

    def json(self):
        return self._payload


class SubmitBetaAppReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = types.ModuleType("submit_beta_app_review")
        exec(compile(SCRIPT.read_text(), SCRIPT, "exec"), cls.module.__dict__)  # noqa: S102

    def test_submit_posts_build_and_prints_submission_json(self):
        post_response = FakeResponse(
            201,
            {
                "data": {
                    "id": "sub-001",
                    "attributes": {"betaReviewState": "WAITING_FOR_REVIEW"},
                }
            },
        )

        with mock.patch.object(self.module, "get_asc_token", return_value="token"), \
                mock.patch.object(
                    self.module,
                    "get_asc_credentials",
                    return_value=("key", "issuer", "pem"),
                ), \
                mock.patch.object(self.module, "requests") as mock_requests, \
                mock.patch.object(sys, "argv", ["submit_beta_app_review.py", "--build-id", "123"]), \
                redirect_stdout(io.StringIO()) as out, \
                redirect_stderr(io.StringIO()) as err:

            mock_requests.post.return_value = post_response

            self.module.main()

            output = json.loads(out.getvalue())

        self.assertEqual(output["submission_id"], "sub-001")
        self.assertEqual(output["build_id"], "123")
        self.assertEqual(output["review_state"], "WAITING_FOR_REVIEW")
        self.assertEqual(mock_requests.post.call_count, 1)
        self.assertEqual(mock_requests.get.call_count, 0)

    def test_submit_with_conflict_fetches_existing_submission(self):
        conflict_response = FakeResponse(409, {"errors": [{"title": "Conflict"}]})
        existing_response = FakeResponse(
            200,
            {
                "data": {
                    "id": "sub-999",
                    "attributes": {"betaReviewState": "APPROVED"},
                }
            },
        )

        with mock.patch.object(self.module, "get_asc_token", return_value="token"), \
                mock.patch.object(
                    self.module,
                    "get_asc_credentials",
                    return_value=("key", "issuer", "pem"),
                ), \
                mock.patch.object(self.module, "requests") as mock_requests:

            mock_requests.post.return_value = conflict_response
            mock_requests.get.return_value = existing_response

            record = self.module.submit_beta_app_review("456", "token")

            self.assertEqual(record["submission_id"], "sub-999")
            self.assertEqual(record["review_state"], "APPROVED")
            mock_requests.post.assert_called_once()
            mock_requests.get.assert_called_once()
            self.assertIn("/v1/builds/456/betaAppReviewSubmission", mock_requests.get.call_args.args[0])

    def test_submit_returns_code_4_when_not_processed_after_retries_exhausted(self):
        unprocessed_response = FakeResponse(
            422,
            {
                "errors": [
                    {
                        "id": "422",
                        "detail": "build not yet processed",
                    }
                ]
            },
        )

        with mock.patch.object(self.module, "get_asc_token", return_value="token"), \
                mock.patch.object(
                    self.module,
                    "get_asc_credentials",
                    return_value=("key", "issuer", "pem"),
                ), \
                mock.patch.object(self.module, "requests") as mock_requests, \
                mock.patch.object(
                    sys, "argv",
                    ["submit_beta_app_review.py", "--build-id", "789",
                     "--max-retries", "0"],
                ), \
                redirect_stdout(io.StringIO()) as out, \
                redirect_stderr(io.StringIO()) as err:

            mock_requests.post.return_value = unprocessed_response

            with self.assertRaises(SystemExit) as ctx:
                self.module.main()

        self.assertEqual(ctx.exception.code, 4)
        self.assertIn("wait_for_build_processed.py", err.getvalue())
        self.assertEqual(out.getvalue(), "")

    def test_submit_retries_on_422_then_succeeds(self):
        unprocessed_response = FakeResponse(
            422,
            {"errors": [{"detail": "build not yet processed"}]},
        )
        success_response = FakeResponse(
            201,
            {
                "data": {
                    "id": "sub-retry",
                    "attributes": {"betaReviewState": "WAITING_FOR_REVIEW"},
                }
            },
        )

        sleep_calls = []

        def fake_sleep(seconds):
            sleep_calls.append(seconds)

        with mock.patch.object(self.module, "get_asc_token", return_value="token"), \
                mock.patch.object(
                    self.module,
                    "get_asc_credentials",
                    return_value=("key", "issuer", "pem"),
                ), \
                mock.patch.object(self.module, "requests") as mock_requests, \
                mock.patch.object(
                    sys, "argv",
                    ["submit_beta_app_review.py", "--build-id", "build-42",
                     "--max-retries", "3", "--retry-interval-seconds", "5"],
                ), \
                redirect_stdout(io.StringIO()) as out, \
                redirect_stderr(io.StringIO()):

            mock_requests.post.side_effect = [
                unprocessed_response,
                unprocessed_response,
                success_response,
            ]

            self.module.main.__globals__["submit_with_retry"].__defaults__ = (
                self.module.DEFAULT_MAX_RETRIES,
                self.module.DEFAULT_RETRY_INTERVAL_SECONDS,
                None,
            )

            original_submit_with_retry = self.module.submit_with_retry

            def patched_submit_with_retry(build_id, token, **kwargs):
                kwargs["sleep_fn"] = fake_sleep
                return original_submit_with_retry(build_id, token, **kwargs)

            with mock.patch.object(
                self.module, "submit_with_retry", side_effect=patched_submit_with_retry
            ):
                self.module.main()

            output = json.loads(out.getvalue())

        self.assertEqual(output["submission_id"], "sub-retry")
        self.assertEqual(output["build_id"], "build-42")
        self.assertEqual(mock_requests.post.call_count, 3)
        self.assertEqual(len(sleep_calls), 2)
        self.assertTrue(all(s == 5 for s in sleep_calls))

    def test_submit_with_retry_exhausts_all_attempts(self):
        unprocessed_response = FakeResponse(
            422,
            {"errors": [{"detail": "not ready"}]},
        )
        sleep_calls = []

        with mock.patch.object(self.module, "requests") as mock_requests:
            mock_requests.post.return_value = unprocessed_response

            with self.assertRaises(self.module.BuildNotProcessedError):
                self.module.submit_with_retry(
                    "build-99",
                    "token",
                    max_retries=2,
                    retry_interval_seconds=1,
                    sleep_fn=lambda s: sleep_calls.append(s),
                )

        self.assertEqual(mock_requests.post.call_count, 3)
        self.assertEqual(len(sleep_calls), 2)

    def test_submit_raises_submission_error_on_missing_data_422(self):
        missing_data_response = FakeResponse(
            422,
            {"errors": [{"detail": "Missing required data"}]},
        )

        with mock.patch.object(self.module, "requests") as mock_requests:
            mock_requests.post.return_value = missing_data_response

            with self.assertRaises(self.module.SubmissionError) as ctx:
                self.module.submit_beta_app_review("build-missing", "token")

        self.assertNotIsInstance(ctx.exception, self.module.BuildNotProcessedError)
        self.assertIn("betaAppReviewDetail", str(ctx.exception))

    def test_submit_does_not_retry_on_missing_data_422(self):
        missing_data_response = FakeResponse(
            422,
            {"errors": [{"detail": "Missing required data"}]},
        )

        with mock.patch.object(self.module, "get_asc_token", return_value="token"), \
                mock.patch.object(
                    self.module,
                    "get_asc_credentials",
                    return_value=("key", "issuer", "pem"),
                ), \
                mock.patch.object(self.module, "requests") as mock_requests, \
                mock.patch.object(
                    sys, "argv",
                    ["submit_beta_app_review.py", "--build-id", "build-m",
                     "--max-retries", "3"],
                ), \
                redirect_stdout(io.StringIO()), \
                redirect_stderr(io.StringIO()):

            mock_requests.post.return_value = missing_data_response

            with self.assertRaises(SystemExit) as ctx:
                self.module.main()

        self.assertEqual(ctx.exception.code, 1)
        self.assertEqual(mock_requests.post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
