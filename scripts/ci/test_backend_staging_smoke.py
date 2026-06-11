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
