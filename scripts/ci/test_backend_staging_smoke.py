import importlib.util
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).with_name("backend_staging_smoke.py")


def load_smoke_module():
    spec = importlib.util.spec_from_file_location("backend_staging_smoke", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_parse_service_filter_accepts_json_array():
    smoke = load_smoke_module()

    assert smoke.parse_service_filter('["lobbying", "health"]') == {"lobbying", "health"}


def test_parse_service_filter_accepts_comma_separated_list():
    smoke = load_smoke_module()

    assert smoke.parse_service_filter("lobbying, health") == {"lobbying", "health"}


def test_parse_service_filter_rejects_non_array_json():
    smoke = load_smoke_module()

    with pytest.raises(smoke.SmokeFailure):
        smoke.parse_service_filter('{"service": "lobbying"}')


def test_lobbying_screen_checks_are_active_when_lobbying_is_selected():
    smoke = load_smoke_module()

    selected_services = {"lobbying"}
    active_names = {
        check.name
        for check in smoke.CHECKS
        if check.service is None or check.service in selected_services
    }

    assert "cabinet-lobbying-overview" in active_names
    assert "lobbyist-organizations:directory" in active_names


def test_load_deployed_services_uses_selected_environment(tmp_path):
    smoke = load_smoke_module()
    manifest = tmp_path / "deployment-services.json"
    manifest.write_text(
        """
        {
          "services": [
            {"name": "staging-only", "deploy": {"staging": true, "production": false}},
            {"name": "production-only", "deploy": {"staging": false, "production": true}}
          ]
        }
        """,
        encoding="utf-8",
    )

    assert smoke.load_deployed_services(manifest, "staging") == {"staging-only"}
    assert smoke.load_deployed_services(manifest, "production") == {"production-only"}


def test_bills_and_members_validators_require_non_empty_lists():
    smoke = load_smoke_module()

    smoke.validate_bills(200, {"bills": [{"id": "C-1"}]})
    smoke.validate_members(200, {"members": [{"id": "123"}]})

    with pytest.raises(smoke.SmokeFailure, match="bills must not be empty"):
        smoke.validate_bills(200, {"bills": []})
    with pytest.raises(smoke.SmokeFailure, match="members must not be empty"):
        smoke.validate_members(200, {"members": []})


def test_bill_diff_route_validator_distinguishes_api_gateway_404():
    smoke = load_smoke_module()

    smoke.validate_bill_diff_route(400, {"error": "missing required query parameters: from, to"})

    with pytest.raises(smoke.SmokeFailure, match="API Gateway returned Not Found"):
        smoke.validate_bill_diff_route(404, {"message": "Not Found"})


def test_bill_diff_full_validator_requires_seeded_payload():
    smoke = load_smoke_module()

    smoke.validate_bill_diff_payload(
        200,
        {
            "from": {"id": smoke.C11_FIRST_READING_VERSION_ID},
            "to": {"id": smoke.C11_COMMITTEE_VERSION_ID},
            "clauses": [{"id": "clause-1"}],
        },
    )

    with pytest.raises(smoke.SmokeFailure, match="clauses must not be empty"):
        smoke.validate_bill_diff_payload(
            200,
            {
                "from": {"id": smoke.C11_FIRST_READING_VERSION_ID},
                "to": {"id": smoke.C11_COMMITTEE_VERSION_ID},
                "clauses": [],
            },
        )


def test_bill_diff_unavailable_validator_requires_empty_204():
    smoke = load_smoke_module()

    smoke.validate_bill_diff_unavailable(204, b"")

    with pytest.raises(smoke.SmokeFailure, match="expected HTTP 204"):
        smoke.validate_bill_diff_unavailable(200, b"")
    with pytest.raises(smoke.SmokeFailure, match="body must be empty"):
        smoke.validate_bill_diff_unavailable(204, b"{}")


def test_bill_diff_unknown_validator_accepts_service_owned_404():
    smoke = load_smoke_module()

    smoke.validate_bill_diff_unknown(404, {"error": "bill not found"})
    smoke.validate_bill_diff_unknown(404, {"error": "version not found"})
    # The bills index can still be warming; a service-owned 503 proves route reachability.
    smoke.validate_bill_diff_unknown(503, {"error": "bills index checksum mismatch"})


def test_bill_diff_unknown_validator_rejects_api_gateway_404():
    smoke = load_smoke_module()

    with pytest.raises(smoke.SmokeFailure, match="API Gateway returned Not Found"):
        smoke.validate_bill_diff_unknown(404, {"message": "Not Found"})

    with pytest.raises(smoke.SmokeFailure, match="service-owned error body"):
        smoke.validate_bill_diff_unknown(404, {})

    with pytest.raises(smoke.SmokeFailure, match="not a documented not-found message"):
        smoke.validate_bill_diff_unknown(404, {"error": "internal error"})


def test_full_only_bill_diff_check_is_skipped_in_contract_mode():
    smoke = load_smoke_module()

    contract_checks = [check.name for check in smoke.CHECKS if not check.full_only]
    full_checks = [check.name for check in smoke.CHECKS]

    assert "bills:diff-route" in contract_checks
    assert "bills:diff-unknown" in contract_checks
    assert "bills:diff-full" not in contract_checks
    assert "bills:diff-one-version" not in contract_checks
    assert "bills:diff-full" in full_checks
    assert "bills:diff-one-version" in full_checks


def test_full_mode_bill_diff_fixtures_use_backfilled_current_parliament_ids():
    smoke = load_smoke_module()

    checks = {check.name: check for check in smoke.CHECKS}

    diff_full = checks["bills:diff-full"]
    assert diff_full.path == "/api/v1/bills/C-11/diff"
    assert diff_full.query == {
        "from": "c-11-13615955-first-reading",
        "to": "c-11-13896514-as-amended-by-committee",
    }

    one_version = checks["bills:diff-one-version"]
    assert one_version.path == "/api/v1/bills/C-10/diff"
    assert one_version.query == {
        "from": "c-10-13610716-first-reading",
        "to": "c-10-13610716-first-reading",
    }
    assert not one_version.expect_json


def test_write_summary_writes_to_github_step_summary(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NO_COLOR", "1")
    smoke = load_smoke_module()
    summary_file = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

    check = smoke.SmokeCheck(
        name="test:check",
        method="GET",
        path="/test",
        query={},
        expected_statuses={200},
        validator=lambda status, payload: None,
        deterministic_note="Deterministic check.",
        fixture_note="No fixture required."
    )

    smoke.write_summary(
        base_url="https://api.test",
        environment="staging",
        results=[(check, True, "HTTP 200")],
        skipped=[]
    )

    # Verify file was written
    assert summary_file.exists()
    content = summary_file.read_text(encoding="utf-8")
    assert "## Backend staging smoke tests" in content
    assert "| test:check | PASS | HTTP 200 |" in content

    # Verify clean console stdout was printed
    captured = capsys.readouterr()
    assert "Backend staging smoke tests summary:" in captured.out
    assert "Base URL: https://api.test" in captured.out
    assert "Passed: 1" in captured.out
    assert "Failed: 0" in captured.out
    # Raw markdown table should NOT be in console stdout
    assert "| Endpoint | Result | Evidence |" not in captured.out
