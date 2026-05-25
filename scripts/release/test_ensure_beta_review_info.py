"""Tests for ensure_beta_review_info.py."""
from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ensure_beta_review_info import (
    ensure_beta_app_review_detail,
    ensure_beta_build_localizations,
)


class TestEnsureBetaAppReviewDetail:
    def test_already_exists_with_contact(self):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "data": {
                "id": "detail-123",
                "attributes": {
                    "contactEmail": "test@example.com",
                    "contactFirstName": "Jane",
                    "contactLastName": "Doe",
                    "contactPhone": "+1555000",
                },
            }
        }
        result = ensure_beta_app_review_detail(
            "app-1", "token",
            "new@example.com", "First", "Last", "+1555000",
            http_get=lambda *a, **kw: mock_resp,
        )
        assert result == {"status": "exists", "id": "detail-123"}

    def test_existing_contact_details_do_not_require_env_values(self):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "data": {
                "id": "detail-123",
                "attributes": {
                    "contactEmail": "test@example.com",
                    "contactFirstName": "Jane",
                    "contactLastName": "Doe",
                    "contactPhone": "+1555000",
                },
            }
        }
        result = ensure_beta_app_review_detail(
            "app-1", "token",
            "", "", "", "",
            http_get=lambda *a, **kw: mock_resp,
        )
        assert result == {"status": "exists", "id": "detail-123"}

    def test_exists_without_contact_patches(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": {
                "id": "detail-456",
                "attributes": {"contactEmail": None},
            }
        }
        patch_resp = MagicMock()
        patch_resp.status_code = 200
        result = ensure_beta_app_review_detail(
            "app-1", "token",
            "contact@example.com", "Jane", "Doe", "+1555111",
            http_get=lambda *a, **kw: get_resp,
            http_patch=lambda *a, **kw: patch_resp,
        )
        assert result == {"status": "updated", "id": "detail-456"}

    def test_missing_contact_input_skips_for_missing_asc_fields(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": {
                "id": "detail-456",
                "attributes": {
                    "contactEmail": "test@example.com",
                    "contactFirstName": "Jane",
                    "contactLastName": "",
                    "contactPhone": "+1555000",
                },
            }
        }
        result = ensure_beta_app_review_detail(
            "app-1", "token",
            "", "", "", "",
            http_get=lambda *a, **kw: get_resp,
        )
        assert result["status"] == "skipped"
        assert result["id"] == "detail-456"
        assert any("contactLastName" in f for f in result["missing_fields"])

    def test_all_contact_fields_missing_skips(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": {
                "id": "detail-456",
                "attributes": {
                    "contactEmail": None,
                    "contactFirstName": None,
                    "contactLastName": None,
                    "contactPhone": None,
                },
            }
        }
        result = ensure_beta_app_review_detail(
            "app-1", "token",
            "", "", "", "",
            http_get=lambda *a, **kw: get_resp,
        )
        assert result["status"] == "skipped"
        assert result["id"] == "detail-456"
        assert len(result["missing_fields"]) == 4

    def test_patch_failure_raises(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": {"id": "detail-789", "attributes": {"contactEmail": ""}}
        }
        patch_resp = MagicMock()
        patch_resp.status_code = 403
        patch_resp.text = "Forbidden"
        with pytest.raises(RuntimeError, match="Failed to update betaAppReviewDetail"):
            ensure_beta_app_review_detail(
                "app-1", "token",
                "x@x.com", "A", "B", "+1",
                http_get=lambda *a, **kw: get_resp,
                http_patch=lambda *a, **kw: patch_resp,
            )

    def test_404_raises(self):
        mock_resp = MagicMock()
        mock_resp.status_code = 404
        mock_resp.text = "Not Found"
        with pytest.raises(RuntimeError, match="not found"):
            ensure_beta_app_review_detail(
                "app-1", "token",
                "x@x.com", "A", "B", "+1",
                http_get=lambda *a, **kw: mock_resp,
            )


class TestEnsureBetaBuildLocalizations:
    def test_localization_already_exists(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": [
                {
                    "id": "loc-1",
                    "attributes": {"locale": "en-US", "whatsNew": "Testing notes"},
                }
            ]
        }
        result = ensure_beta_build_localizations(
            "build-1", "token", "New notes",
            http_get=lambda *a, **kw: get_resp,
        )
        assert result == {"status": "exists", "id": "loc-1", "locale": "en-US"}

    def test_creates_when_missing(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {"data": []}

        post_resp = MagicMock()
        post_resp.status_code = 201
        post_resp.json.return_value = {"data": {"id": "loc-new"}}

        result = ensure_beta_build_localizations(
            "build-2", "token", "What to test",
            http_get=lambda *a, **kw: get_resp,
            http_post=lambda *a, **kw: post_resp,
        )
        assert result == {"status": "created", "id": "loc-new", "locale": "en-US"}

    def test_conflict_treated_as_exists(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {"data": []}

        post_resp = MagicMock()
        post_resp.status_code = 409

        result = ensure_beta_build_localizations(
            "build-3", "token", "Notes",
            http_get=lambda *a, **kw: get_resp,
            http_post=lambda *a, **kw: post_resp,
        )
        assert result == {"status": "exists", "id": "", "locale": "en-US"}

    def test_create_failure_raises(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {"data": []}

        post_resp = MagicMock()
        post_resp.status_code = 400
        post_resp.text = "Bad Request"

        with pytest.raises(RuntimeError, match="Failed to create betaBuildLocalization"):
            ensure_beta_build_localizations(
                "build-4", "token", "Notes",
                http_get=lambda *a, **kw: get_resp,
                http_post=lambda *a, **kw: post_resp,
            )

    def test_different_locale_creates_new(self):
        get_resp = MagicMock()
        get_resp.status_code = 200
        get_resp.json.return_value = {
            "data": [
                {"id": "loc-fr", "attributes": {"locale": "fr-CA", "whatsNew": "French notes"}}
            ]
        }

        post_resp = MagicMock()
        post_resp.status_code = 201
        post_resp.json.return_value = {"data": {"id": "loc-en"}}

        result = ensure_beta_build_localizations(
            "build-5", "token", "English notes", locale="en-US",
            http_get=lambda *a, **kw: get_resp,
            http_post=lambda *a, **kw: post_resp,
        )
        assert result == {"status": "created", "id": "loc-en", "locale": "en-US"}
