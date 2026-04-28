#!/usr/bin/env python3
from __future__ import annotations

import unittest
from unittest import mock

import fetch_releases


class FetchReleasesTests(unittest.TestCase):
    def test_version_from_tag_extracts_semver(self) -> None:
        self.assertEqual(fetch_releases.version_from_tag("v1.9.0"), "1.9.0")
        self.assertEqual(fetch_releases.version_from_tag("release-2.1"), "2.1")
        self.assertEqual(fetch_releases.version_from_tag("latest"), "")

    def test_version_aliases_include_two_part_version_for_patch_zero(self) -> None:
        self.assertEqual(fetch_releases.version_aliases("1.9.0"), {"1.9.0", "1.9"})
        self.assertEqual(fetch_releases.version_aliases("1.9"), {"1.9", "1.9.0"})

    def test_notes_are_truncated_to_dashboard_limit(self) -> None:
        notes = "x" * 600
        truncated = fetch_releases.truncate_notes(notes)

        self.assertEqual(len(truncated), fetch_releases.MAX_NOTES_CHARS)
        self.assertTrue(truncated.endswith("..."))

    def test_fetch_app_store_versions_uses_supported_relationship_params(self) -> None:
        response = {
            "data": [
                {
                    "attributes": {
                        "versionString": "1.8",
                        "appStoreState": "READY_FOR_SALE",
                        "createdDate": "2026-01-26T17:09:00-08:00",
                    }
                },
                {
                    "attributes": {
                        "versionString": "1.9",
                        "appStoreState": "WAITING_FOR_REVIEW",
                        "createdDate": "2026-02-18T10:44:41-08:00",
                    }
                },
            ]
        }
        with mock.patch.object(fetch_releases, "get_json", return_value=response) as get_json:
            versions = fetch_releases.fetch_app_store_versions({"Authorization": "Bearer token"})

        params = get_json.call_args.kwargs["params"]
        self.assertNotIn("sort", params)
        self.assertEqual(versions[0]["version"], "1.9")
        self.assertEqual(versions[0]["status_label"], "Waiting for Review")

    def test_merge_releases_adds_matching_app_store_status(self) -> None:
        github_releases = [
            {
                "tag_name": "v1.9.0",
                "name": "epac 1.9",
                "published_at": "2026-04-28T18:00:00Z",
                "created_at": "2026-04-28T17:00:00Z",
                "body": "Release notes",
                "html_url": "https://github.com/RiddimSoftware/epac/releases/tag/v1.9.0",
            }
        ]
        app_versions = [
            {
                "version": "1.9",
                "state": "READY_FOR_SALE",
                "status_label": "On App Store",
                "created_at": "2026-04-28T16:00:00Z",
            }
        ]

        releases = fetch_releases.merge_releases(github_releases, app_versions)

        self.assertEqual(releases[0]["version"], "1.9.0")
        self.assertEqual(releases[0]["status_label"], "On App Store")
        self.assertEqual(releases[0]["app_store_state"], "READY_FOR_SALE")


if __name__ == "__main__":
    unittest.main()
