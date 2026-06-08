#!/usr/bin/env python3
"""Print the UDID for the first connected physical iOS 26+ perf-test device."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path


def major_version(value: str | None) -> int:
    if not value:
        return 0
    try:
        return int(value.split(".", maxsplit=1)[0])
    except ValueError:
        return 0


def find_ios_perf_device_udid(data: dict) -> str | None:
    for device in data.get("result", {}).get("devices", []):
        connection = device.get("connectionProperties") or {}
        hardware = device.get("hardwareProperties") or {}
        properties = device.get("deviceProperties") or {}
        if connection.get("tunnelState") != "connected":
            continue
        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("deviceType") not in {"iPhone", "iPad"}:
            continue
        if major_version(properties.get("osVersionNumber")) < 26:
            continue
        udid = hardware.get("udid")
        if udid:
            return udid
    return None


def main() -> int:
    with tempfile.TemporaryDirectory() as temp_dir:
        output = Path(temp_dir) / "devices.json"
        command = ["xcrun", "devicectl", "list", "devices", "--json-output", str(output)]
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        data = json.loads(output.read_text(encoding="utf-8"))

    udid = find_ios_perf_device_udid(data)
    if udid:
        print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
