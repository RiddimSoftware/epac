#!/usr/bin/env python3
"""Unit tests for the CI failure Linear reporter."""

from __future__ import annotations

from pathlib import Path
import json
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import ci_failure_to_linear


def outcome(conclusion: str = "failure") -> ci_failure_to_linear.CIWorkflowOutcome:
    return ci_failure_to_linear.CIWorkflowOutcome(
        workflow_name="Backend PR",
        run_url="https://github.com/RiddimSoftware/epac/actions/runs/123",
        head_sha="abc123",
        branch="feature-branch",
        conclusion=conclusion,
        repo="RiddimSoftware/epac",
    )


class FakeLinearClient:
    def __init__(self) -> None:
        self.created: list[ci_failure_to_linear.LinearIssueRequest] = []

    def create_issue(self, issue: ci_failure_to_linear.LinearIssueRequest) -> dict[str, str]:
        self.created.append(issue)
        return {"identifier": "EPAC-999", "url": "https://linear.app/riddimsoftware/issue/EPAC-999"}


def test_failure_path_creates_expected_linear_issue_request() -> None:
    client = FakeLinearClient()

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome(),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    assert created == {"identifier": "EPAC-999", "url": "https://linear.app/riddimsoftware/issue/EPAC-999"}
    assert client.created == [
        ci_failure_to_linear.LinearIssueRequest(
            title="CI: Backend PR failed on feature-branch",
            description="Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
            priority=1,
            state="Todo",
            team_key="EPAC",
        )
    ]


def test_success_path_is_noop() -> None:
    client = FakeLinearClient()

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome("success"),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    assert created is None
    assert client.created == []


def test_missing_linear_api_token_exits_nonzero_with_clear_message(monkeypatch, capsys) -> None:
    monkeypatch.delenv("LINEAR_API_TOKEN", raising=False)
    for handler in ci_failure_to_linear.logger.handlers:
        if hasattr(handler, "stream"):
            handler.stream = sys.stderr

    code = ci_failure_to_linear.main(
        [
            "--workflow-name",
            "Backend PR",
            "--run-url",
            "https://github.com/RiddimSoftware/epac/actions/runs/123",
            "--head-sha",
            "abc123",
            "--branch",
            "feature-branch",
            "--conclusion",
            "failure",
            "--repo",
            "RiddimSoftware/epac",
            "--team-key",
            "EPAC",
        ]
    )

    captured = capsys.readouterr()
    assert code == 1
    assert "LINEAR_API_TOKEN is required" in captured.err


def test_team_key_lookup_is_cached_for_run() -> None:
    requests: list[dict] = []

    def fake_transport(payload: dict, _headers: dict[str, str]) -> tuple[int, str]:
        requests.append(payload)
        if "ResolveTeam" in payload["query"]:
            return (
                200,
                json.dumps(
                    {
                        "data": {
                            "team": {
                                "id": "team-123",
                                "states": {
                                    "nodes": [
                                        {"id": "state-todo", "name": "Todo", "type": "unstarted"}
                                    ]
                                },
                            }
                        }
                    }
                ),
            )
        return (
            200,
            json.dumps(
                {
                    "data": {
                        "issueCreate": {
                            "success": True,
                            "issue": {"identifier": "EPAC-999", "url": "https://linear.example/EPAC-999"},
                        }
                    }
                }
            ),
        )

    client = ci_failure_to_linear.LinearClient("token", transport=fake_transport, sleep=lambda _seconds: None)
    issue = ci_failure_to_linear.LinearIssueRequest(
        title="CI: Backend PR failed on branch",
        description="Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
        priority=1,
        state="Todo",
        team_key="EPAC",
    )

    client.create_issue(issue)
    client.create_issue(issue)

    team_requests = [payload for payload in requests if "ResolveTeam" in payload["query"]]
    issue_requests = [payload for payload in requests if "CreateCIWorkflowFailureIssue" in payload["query"]]
    assert len(team_requests) == 1
    assert len(issue_requests) == 2
    assert issue_requests[0]["variables"]["input"] == {
        "teamId": "team-123",
        "title": "CI: Backend PR failed on branch",
        "description": "Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
        "priority": 1,
        "stateId": "state-todo",
    }
