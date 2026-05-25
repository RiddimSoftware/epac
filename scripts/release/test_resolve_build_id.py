from types import SimpleNamespace

from scripts.release import resolve_build_id as resolver


class FakeClock:
    def __init__(self):
        self.now = 0
        self.sleep_calls = []

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.sleep_calls.append(seconds)
        self.now += seconds


def build_payload(build_id="build-1", build_number="132", marketing_version="1.12"):
    return {
        "data": [
            {
                "id": build_id,
                "type": "builds",
                "attributes": {
                    "version": build_number,
                    "processingState": "PROCESSING",
                },
                "relationships": {
                    "preReleaseVersion": {
                        "data": {
                            "id": "prv-1",
                            "type": "preReleaseVersions",
                        }
                    }
                },
            }
        ],
        "included": [
            {
                "id": "prv-1",
                "type": "preReleaseVersions",
                "attributes": {
                    "version": marketing_version,
                },
            }
        ],
    }


def response(payload):
    return SimpleNamespace(
        json=lambda: payload,
        raise_for_status=lambda: None,
    )


def test_find_matching_build_id_matches_pre_release_version():
    payload = build_payload()

    build_id = resolver.find_matching_build_id(payload, "1.12")

    assert build_id == "build-1"


def test_find_matching_build_id_ignores_wrong_marketing_version():
    payload = build_payload(marketing_version="1.11")

    build_id = resolver.find_matching_build_id(payload, "1.12")

    assert build_id is None


def test_resolve_build_id_waits_until_build_appears():
    clock = FakeClock()
    responses = [
        response({"data": [], "included": []}),
        response({"data": [], "included": []}),
        response(build_payload()),
    ]
    calls = []

    def fake_get(url, headers=None, params=None, timeout=None):
        calls.append((url, headers, params, timeout))
        return responses.pop(0)

    build_id = resolver.resolve_build_id(
        "1224459142",
        "1.12",
        "132",
        "token",
        timeout_seconds=120,
        poll_interval_seconds=30,
        current_time=clock.time,
        sleep=clock.sleep,
        get_fn=fake_get,
    )

    assert build_id == "build-1"
    assert clock.sleep_calls == [30, 30]
    assert len(calls) == 3
    assert calls[0][2]["filter[app]"] == "1224459142"
    assert calls[0][2]["filter[version]"] == "132"
    assert calls[0][2]["fields[builds]"] == "version,processingState,preReleaseVersion"


def test_resolve_build_id_returns_none_after_timeout():
    clock = FakeClock()
    calls = []

    def fake_get(url, headers=None, params=None, timeout=None):
        calls.append((url, headers, params, timeout))
        return response({"data": [], "included": []})

    build_id = resolver.resolve_build_id(
        "1224459142",
        "1.12",
        "132",
        "token",
        timeout_seconds=60,
        poll_interval_seconds=30,
        current_time=clock.time,
        sleep=clock.sleep,
        get_fn=fake_get,
    )

    assert build_id is None
    assert clock.sleep_calls == [30, 30]
    assert len(calls) == 3
