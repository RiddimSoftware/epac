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
