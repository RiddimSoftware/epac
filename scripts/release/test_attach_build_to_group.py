import json
from types import SimpleNamespace

import pytest

from scripts.release import attach_build_to_group as attach


class FakeCompletedProcess:
    def __init__(self, stdout):
        self.stdout = stdout


def _secret_result():
    return """{"key_id":"K123","issuer_id":"I456","private_key":"PEM"}"""


def _ok_group(group_id: str):
    return SimpleNamespace(
        status_code=200,
        text="{\"data\": [{\"id\": \"%s\"}] }" % group_id,
        json=lambda: {"data": [{"id": group_id}]},
    )


def _empty_group():
    return SimpleNamespace(
        status_code=200,
        text="{\"data\": []}",
        json=lambda: {"data": []},
    )


def _build_attached():
    return SimpleNamespace(status_code=201, text="", json=lambda: {"data": {}})


def _already_attached():
    return SimpleNamespace(
        status_code=409,
        text="{\"errors\": []}",
        json=lambda: {"errors": []},
    )


def _server_error():
    return SimpleNamespace(status_code=500, text="error", json=lambda: {"errors": []})


def test_find_group_id_success(monkeypatch):
    calls = []

    def fake_request(method, url, headers=None, timeout=None, params=None, **_):
        calls.append((method, url, params))
        assert url == f"{attach.BASE_URL}/betaGroups"
        assert headers and headers["Authorization"].startswith("Bearer ")
        return _ok_group("group-1")

    monkeypatch.setattr(attach.requests, "request", fake_request)
    group_id = attach.find_group_id("PublicTesting", "token", bundle_id=None)
    assert group_id == "group-1"
    assert calls == [
        (
            "GET",
            f"{attach.BASE_URL}/betaGroups",
            {"filter[name]": "PublicTesting", "limit": "200"},
        )
    ]


def test_attach_build_success(monkeypatch):
    calls = []

    def fake_request(method, url, headers=None, timeout=None, json=None, **_):
        calls.append((method, url, json))
        return _build_attached()

    monkeypatch.setattr(attach.requests, "request", fake_request)
    result = attach.attach_build("group-1", "123", "token")
    assert result == {"attached": True, "build_id": "123", "group_id": "group-1"}
    assert calls == [
        (
            "POST",
            f"{attach.BASE_URL}/betaGroups/group-1/relationships/builds",
            {"data": [{"type": "builds", "id": "123"}]},
        )
    ]


def test_attach_build_idempotent(monkeypatch):
    def fake_request(method, url, headers=None, timeout=None, json=None, **_):
        return _already_attached()

    monkeypatch.setattr(attach.requests, "request", fake_request)
    result = attach.attach_build("group-1", "123", "token")
    assert result == {"attached": False, "reason": "already_attached"}


def test_find_group_id_missing_returns_exit_code_3(monkeypatch, capsys):
    monkeypatch.setattr(attach, "get_asc_token", lambda *_: "token")
    def fake_request(method, url, headers=None, timeout=None, params=None, **_):
        return _empty_group()

    monkeypatch.setattr(attach.requests, "request", fake_request)
    monkeypatch.setattr(attach.subprocess, "run", lambda *_, **__: FakeCompletedProcess(_secret_result()))

    exit_code = attach.main(["--build-id", "123", "--group-name", "PublicTesting"])
    assert exit_code == 3
    output = json.loads(capsys.readouterr().out)
    assert output["error"] == "group_not_found"
    assert output["group_name"] == "PublicTesting"


def test_request_with_retries_retries_only_transient_server_errors(monkeypatch):
    attempts = []

    def fake_request(method, url, headers=None, timeout=None, params=None, **kwargs):
        attempts.append((method, url))
        if len(attempts) < 3:
            return _server_error()
        return _ok_group("group-1")

    monkeypatch.setattr(attach.requests, "request", fake_request)
    response = attach.request_with_retries("GET", "/betaGroups", "token", max_retries=3)
    assert response.status_code == 200
    assert len(attempts) == 3
