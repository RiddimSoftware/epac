#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parent / "ensure_public_testing_group.py"
ACTUAL_BUNDLE_ID = "net.dinglebox.cabinetdoor"


def complete_beta_review_detail():
    return {
        "data": {
            "id": "review-detail-1",
            "attributes": {
                "contactFirstName": "Release",
                "contactLastName": "Owner",
                "contactPhone": "+14165550123",
                "contactEmail": "release@example.com",
                "demoAccountRequired": False,
                "notes": "Review notes",
            },
        }
    }


def load_module():
    spec = importlib.util.spec_from_file_location("ensure_public_testing_group", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeASCClient:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def request(self, method, path, step, **kwargs):
        self.calls.append(
            {
                "method": method,
                "path": path,
                "step": step,
                "params": kwargs.get("params"),
                "json": kwargs.get("json"),
            }
        )
        if not self.responses:
            raise AssertionError(f"unexpected request: {method} {path}")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class EnsurePublicTestingGroupTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_existing_group_attaches_latest_valid_build_and_submits_review(self):
        client = FakeASCClient(
            [
                {"data": [{"id": "app-1", "attributes": {"bundleId": ACTUAL_BUNDLE_ID}}]},
                {"data": [{"id": "group-1", "attributes": {"name": "PublicTesting"}}]},
                {
                    "data": [
                        {
                            "id": "build-older",
                            "attributes": {
                                "version": "42",
                                "uploadedDate": "2026-05-17T20:00:00Z",
                            },
                            "relationships": {"preReleaseVersion": {"data": {"id": "prv-1"}}},
                        },
                        {
                            "id": "build-latest",
                            "attributes": {
                                "version": "43",
                                "uploadedDate": "2026-05-18T20:00:00Z",
                            },
                            "relationships": {"preReleaseVersion": {"data": {"id": "prv-2"}}},
                        },
                    ],
                    "included": [
                        {"type": "preReleaseVersions", "id": "prv-1", "attributes": {"version": "1.2"}},
                        {"type": "preReleaseVersions", "id": "prv-2", "attributes": {"version": "1.3"}},
                    ],
                },
                complete_beta_review_detail(),
                {
                    "data": [
                        {
                            "id": "beta-loc-1",
                            "attributes": {"locale": "en-US", "description": None},
                        }
                    ]
                },
                {"data": {"id": "beta-loc-1"}},
                {"data": []},
                {},
                {},
                {"data": []},
                {
                    "data": {
                        "id": "submission-1",
                        "attributes": {"betaReviewState": "WAITING_FOR_REVIEW"},
                    }
                },
            ]
        )

        summary = self.module.ensure_public_testing_group(
            client,
            bundle_id=ACTUAL_BUNDLE_ID,
            group_name="PublicTesting",
            dry_run=False,
        )

        self.assertEqual(
            summary,
            {
                "group_id": "group-1",
                "group_name": "PublicTesting",
                "build_id": "build-latest",
                "build_version": "1.3",
                "review_status": "WAITING_FOR_REVIEW",
            },
        )
        self.assertEqual(
            [call["path"] for call in client.calls],
            [
                "/apps",
                "/apps/app-1/betaGroups",
                "/builds",
                "/apps/app-1/betaAppReviewDetail",
                "/apps/app-1/betaAppLocalizations",
                "/betaAppLocalizations/beta-loc-1",
                "/builds/build-latest/betaBuildLocalizations",
                "/betaBuildLocalizations",
                "/betaGroups/group-1/relationships/builds",
                "/builds/build-latest/betaAppReviewSubmission",
                "/betaAppReviewSubmissions",
            ],
        )
        self.assertNotIn("filter[name]", client.calls[1]["params"])
        self.assertEqual(client.calls[2]["params"]["sort"], "-uploadedDate")
        self.assertEqual(
            client.calls[8]["json"],
            {"data": [{"type": "builds", "id": "build-latest"}]},
        )
        self.assertEqual(
            client.calls[10]["json"],
            {
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": "build-latest"}}
                    },
                }
            },
        )

    def test_creates_group_with_public_link_disabled_when_missing(self):
        client = FakeASCClient(
            [
                {"data": [{"id": "app-1", "attributes": {"bundleId": ACTUAL_BUNDLE_ID}}]},
                {"data": []},
                {"data": {"id": "group-2", "attributes": {"name": "PublicTesting"}}},
                {
                    "data": [
                        {
                            "id": "build-1",
                            "attributes": {
                                "version": "44",
                                "uploadedDate": "2026-05-18T20:00:00Z",
                            },
                            "relationships": {"preReleaseVersion": {"data": {"id": "prv-1"}}},
                        }
                    ],
                    "included": [{"type": "preReleaseVersions", "id": "prv-1", "attributes": {"version": "1.3"}}],
                },
                complete_beta_review_detail(),
                {
                    "data": [
                        {
                            "id": "beta-loc-1",
                            "attributes": {
                                "locale": "en-US",
                                "description": "Already set",
                            },
                        }
                    ]
                },
                {"data": []},
                {},
                {"data": []},
                {
                    "data": {
                        "id": "submission-1",
                        "attributes": {"betaReviewState": "APPROVED"},
                    }
                },
            ]
        )

        summary = self.module.ensure_public_testing_group(
            client,
            bundle_id=ACTUAL_BUNDLE_ID,
            group_name="PublicTesting",
            dry_run=False,
        )

        self.assertEqual(summary["group_id"], "group-2")
        create_call = client.calls[2]
        self.assertEqual(create_call["method"], "POST")
        self.assertEqual(create_call["path"], "/betaGroups")
        self.assertEqual(
            create_call["json"]["data"]["attributes"],
            {
                "name": "PublicTesting",
                "publicLinkEnabled": False,
                "publicLinkLimitEnabled": False,
                "feedbackEnabled": True,
            },
        )

    def test_existing_beta_review_submission_is_idempotent(self):
        client = FakeASCClient(
            [
                {"data": [{"id": "app-1", "attributes": {"bundleId": ACTUAL_BUNDLE_ID}}]},
                {"data": [{"id": "group-1", "attributes": {"name": "PublicTesting"}}]},
                {
                    "data": [
                        {
                            "id": "build-1",
                            "attributes": {
                                "version": "44",
                                "uploadedDate": "2026-05-18T20:00:00Z",
                            },
                            "relationships": {"preReleaseVersion": {"data": {"id": "prv-1"}}},
                        }
                    ],
                    "included": [{"type": "preReleaseVersions", "id": "prv-1", "attributes": {"version": "1.3"}}],
                },
                complete_beta_review_detail(),
                {
                    "data": [
                        {
                            "id": "beta-loc-1",
                            "attributes": {
                                "locale": "en-US",
                                "description": "Already set",
                            },
                        }
                    ]
                },
                {"data": [{"id": "loc-1", "attributes": {"locale": "en-US", "whatsNew": "Ready"}}]},
                {},
                {
                    "data": {
                        "id": "submission-1",
                        "attributes": {"betaReviewState": "IN_REVIEW"},
                    }
                },
            ]
        )

        summary = self.module.ensure_public_testing_group(
            client,
            bundle_id=ACTUAL_BUNDLE_ID,
            group_name="PublicTesting",
            dry_run=False,
        )

        self.assertEqual(summary["review_status"], "IN_REVIEW")
        self.assertNotIn("/betaAppReviewSubmissions", [call["path"] for call in client.calls])

    def test_stale_linear_bundle_id_is_mapped_to_actual_epac_bundle(self):
        client = FakeASCClient(
            [
                {"data": []},
                {"data": [{"id": "app-1", "attributes": {"bundleId": ACTUAL_BUNDLE_ID}}]},
            ]
        )

        app = self.module.find_app(client, "ca.riddimsoftware.epac")

        self.assertEqual(app["id"], "app-1")
        self.assertEqual(client.calls[0]["params"]["filter[bundleId]"], "ca.riddimsoftware.epac")
        self.assertEqual(client.calls[1]["params"]["filter[bundleId]"], ACTUAL_BUNDLE_ID)

    def test_missing_beta_app_review_contact_details_fails_actionably(self):
        client = FakeASCClient(
            [
                {
                    "data": {
                        "id": "review-detail-1",
                        "attributes": {
                            "contactFirstName": None,
                            "contactLastName": "",
                            "contactPhone": None,
                            "contactEmail": "",
                            "demoAccountRequired": None,
                            "notes": "",
                        },
                    }
                }
            ]
        )

        with self.assertRaises(self.module.SetupError) as raised:
            self.module.ensure_beta_app_review_details(client, "app-1", {})

        self.assertEqual(raised.exception.step, "ensure_beta_app_review_details")
        self.assertIn("ASC_BETA_REVIEW_CONTACT_FIRST_NAME", str(raised.exception))
        self.assertEqual([call["path"] for call in client.calls], ["/apps/app-1/betaAppReviewDetail"])

    def test_beta_app_review_details_are_patched_from_config_when_missing(self):
        client = FakeASCClient(
            [
                {
                    "data": {
                        "id": "review-detail-1",
                        "attributes": {
                            "contactFirstName": None,
                            "contactLastName": None,
                            "contactPhone": None,
                            "contactEmail": None,
                            "demoAccountRequired": None,
                            "notes": None,
                        },
                    }
                },
                {"data": {"id": "review-detail-1"}},
            ]
        )

        self.module.ensure_beta_app_review_details(
            client,
            "app-1",
            {
                "contactFirstName": "Release",
                "contactLastName": "Owner",
                "contactPhone": "+14165550123",
                "contactEmail": "release@example.com",
                "notes": "Review notes",
            },
        )

        self.assertEqual(client.calls[1]["method"], "PATCH")
        self.assertEqual(client.calls[1]["path"], "/betaAppReviewDetails/review-detail-1")
        self.assertEqual(
            client.calls[1]["json"]["data"]["attributes"],
            {
                "contactFirstName": "Release",
                "contactLastName": "Owner",
                "contactPhone": "+14165550123",
                "contactEmail": "release@example.com",
                "demoAccountRequired": False,
                "notes": "Review notes",
            },
        )

    def test_empty_beta_build_whats_new_is_patched(self):
        client = FakeASCClient(
            [
                {"data": [{"id": "loc-1", "attributes": {"locale": "en-US", "whatsNew": ""}}]},
                {"data": {"id": "loc-1"}},
            ]
        )

        self.module.ensure_beta_build_localization(client, "build-1")

        self.assertEqual(client.calls[1]["method"], "PATCH")
        self.assertEqual(client.calls[1]["path"], "/betaBuildLocalizations/loc-1")
        self.assertEqual(
            client.calls[1]["json"]["data"]["attributes"],
            {"whatsNew": self.module.DEFAULT_WHATS_NEW},
        )

    def test_api_error_prints_structured_json_to_stderr(self):
        error = self.module.ASCAPIError(
            step="list_apps",
            method="GET",
            path="/apps",
            status_code=403,
            response={"errors": [{"detail": "forbidden"}]},
        )
        with tempfile.TemporaryFile(mode="w+") as stderr:
            code = self.module.handle_error(error, stderr=stderr)
            stderr.seek(0)
            payload = json.load(stderr)

        self.assertEqual(code, 1)
        self.assertEqual(payload["error"], "asc_api_error")
        self.assertEqual(payload["step"], "list_apps")
        self.assertEqual(payload["status_code"], 403)
        self.assertEqual(payload["response"], {"errors": [{"detail": "forbidden"}]})


if __name__ == "__main__":
    unittest.main()
