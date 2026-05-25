import json

import pytest

from scripts.release import wait_for_build_processed as wf


def build_payload(state: str, expired=False, errors=None, uses_non_exempt_encryption=None):
    attrs = {
        "processingState": state,
        "expired": expired,
    }
    if uses_non_exempt_encryption is not None:
        attrs["usesNonExemptEncryption"] = uses_non_exempt_encryption
    payload = {
        "data": {
            "id": "b1",
            "type": "builds",
            "attributes": attrs,
        }
    }
    if state == "INVALID" and errors is not None:
        payload["errors"] = errors
    return payload


class FakeClock:
    def __init__(self, start: float = 0.0):
        self.now = start
        self.sleep_calls: list[float] = []

    def time(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleep_calls.append(seconds)
        self.now += seconds


def test_waits_until_valid():
    clock = FakeClock()
    responses = [
        build_payload("PROCESSING"),
        build_payload("PROCESSING"),
        build_payload("VALID", uses_non_exempt_encryption=False),
    ]

    def get_build(_build_id: str, _token: str):
        return responses.pop(0)

    status, payload = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=240,
        poll_interval_seconds=60,
        current_time=clock.time,
        sleep=clock.sleep,
        get_build_fn=get_build,
    )

    assert status == 0
    assert payload["build_id"] == "b1"
    assert payload["processing_state"] == "VALID"
    assert payload["wait_seconds"] == 120
    assert responses == []
    assert clock.sleep_calls == [60, 60]


def test_waits_for_compliance_after_valid():
    clock = FakeClock()
    responses = [
        build_payload("VALID"),
        build_payload("VALID"),
        build_payload("VALID", uses_non_exempt_encryption=False),
    ]

    def get_build(_build_id: str, _token: str):
        return responses.pop(0)

    status, payload = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=600,
        poll_interval_seconds=60,
        current_time=clock.time,
        sleep=clock.sleep,
        get_build_fn=get_build,
    )

    assert status == 0
    assert payload["processing_state"] == "VALID"
    assert payload["wait_seconds"] == 120
    assert clock.sleep_calls == [60, 60]


def test_compliance_timeout():
    clock = FakeClock()
    responses = [build_payload("VALID")] * 4

    def get_build(_build_id: str, _token: str):
        return responses.pop(0)

    status, payload = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=120,
        poll_interval_seconds=60,
        current_time=clock.time,
        sleep=clock.sleep,
        get_build_fn=get_build,
    )

    assert status == 5
    assert payload["timed_out"] is True
    assert payload["last_state"] == "VALID_MISSING_COMPLIANCE"


def test_times_out_with_structured_output():
    clock = FakeClock()
    responses = [build_payload("PROCESSING")] * 4

    def get_build(_build_id: str, _token: str):
        return responses.pop(0)

    status, payload = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=120,
        poll_interval_seconds=60,
        current_time=clock.time,
        sleep=clock.sleep,
        get_build_fn=get_build,
    )

    assert status == 5
    assert payload["timed_out"] is True
    assert payload["last_state"] == "PROCESSING"
    assert payload["elapsed_seconds"] == 120
    assert payload["build_id"] == "b1"
    assert len(clock.sleep_calls) == 2
    assert len(responses) == 1


def test_invalid_state_returns_rejection_details():
    errors = [{"code": "INVALID_STATE", "title": "Invalid", "detail": "Binary failed upload"}]
    responses = [
        build_payload("PROCESSING"),
        build_payload("INVALID", errors=errors),
    ]

    def get_build(_build_id: str, _token: str):
        return responses.pop(0)

    status, payload = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=240,
        poll_interval_seconds=15,
        current_time=FakeClock().time,
        sleep=FakeClock().sleep,
        get_build_fn=get_build,
    )

    assert status == 6
    assert payload["processing_state"] == "INVALID"
    assert payload["rejection"] == [
        {"code": "INVALID_STATE", "id": None, "status": None, "title": "Invalid", "detail": "Binary failed upload"}
    ]
    assert payload["wait_seconds"] == 0


def test_extracts_rejection_details_from_payload():
    result = wf.extract_rejection_reason({"errors": [{"code": "X", "detail": "y"}]})
    assert result == [{"code": "X", "id": None, "status": None, "title": None, "detail": "y"}]


def test_expired_build_aborts_with_code_7():
    payload = build_payload("VALID", expired=True)
    status, result = wf.wait_for_build_processed(
        "b1",
        "token",
        timeout_seconds=999,
        poll_interval_seconds=60,
        current_time=FakeClock().time,
        sleep=FakeClock().sleep,
        get_build_fn=lambda _build_id, _token: payload,
    )

    assert status == 7
    assert result["expired"] is True
    assert result["processing_state"] == "VALID"
