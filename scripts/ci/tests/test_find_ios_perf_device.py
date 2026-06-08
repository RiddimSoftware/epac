from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "find_ios_perf_device.py"
SPEC = importlib.util.spec_from_file_location("find_ios_perf_device", MODULE_PATH)
assert SPEC is not None
find_ios_perf_device = importlib.util.module_from_spec(SPEC)
sys.modules["find_ios_perf_device"] = find_ios_perf_device
assert SPEC.loader is not None
SPEC.loader.exec_module(find_ios_perf_device)


def device(
    *,
    udid: str,
    platform: str,
    device_type: str,
    os_version: str,
    tunnel_state: str,
) -> dict:
    return {
        "capabilities": [],
        "connectionProperties": {
            "pairingState": "paired",
            "transportType": "wired",
            "tunnelState": tunnel_state,
        },
        "deviceProperties": {
            "name": udid,
            "osVersionNumber": os_version,
        },
        "hardwareProperties": {
            "deviceType": device_type,
            "platform": platform,
            "udid": udid,
        },
        "identifier": udid,
        "tags": [],
        "visibilityClass": "default",
    }


def test_finds_connected_ios_26_phone_only() -> None:
    devicectl_output = {
        "result": {
            "devices": [
                device(
                    udid="OFFLINE-IOS-26-IPAD",
                    platform="iOS",
                    device_type="iPad",
                    os_version="26.5",
                    tunnel_state="disconnected",
                ),
                device(
                    udid="CONNECTED-IOS-18-IPHONE",
                    platform="iOS",
                    device_type="iPhone",
                    os_version="18.7",
                    tunnel_state="connected",
                ),
                device(
                    udid="CONNECTED-WATCH",
                    platform="watchOS",
                    device_type="Apple Watch",
                    os_version="26.0",
                    tunnel_state="connected",
                ),
                device(
                    udid="CONNECTED-IOS-26-IPHONE",
                    platform="iOS",
                    device_type="iPhone",
                    os_version="26.5",
                    tunnel_state="connected",
                ),
            ]
        }
    }

    assert (
        find_ios_perf_device.find_ios_perf_device_udid(devicectl_output)
        == "CONNECTED-IOS-26-IPHONE"
    )
