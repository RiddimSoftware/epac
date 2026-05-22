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

    def test_submit_returns_code_4_when_not_processed(self):
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
                mock.patch.object(sys, "argv", ["submit_beta_app_review.py", "--build-id", "789"]), \
                redirect_stdout(io.StringIO()) as out, \
                redirect_stderr(io.StringIO()) as err:

            mock_requests.post.return_value = unprocessed_response

            with self.assertRaises(SystemExit) as ctx:
                self.module.main()

        self.assertEqual(ctx.exception.code, 4)
        self.assertIn("wait_for_build_processed.py", err.getvalue())
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
