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
            "from": {"id": "C-8-v1"},
            "to": {"id": "C-8-v3"},
            "clauses": [{"id": "clause-1"}],
        },
    )

    with pytest.raises(smoke.SmokeFailure, match="clauses must not be empty"):
        smoke.validate_bill_diff_payload(
            200,
            {"from": {"id": "C-8-v1"}, "to": {"id": "C-8-v3"}, "clauses": []},
        )


def test_full_only_bill_diff_check_is_skipped_in_contract_mode():
    smoke = load_smoke_module()

    contract_checks = [check.name for check in smoke.CHECKS if not check.full_only]
    full_checks = [check.name for check in smoke.CHECKS]

    assert "bills:diff-route" in contract_checks
    assert "bills:diff-full" not in contract_checks
    assert "bills:diff-full" in full_checks
