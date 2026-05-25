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
        head_sha="abc12345deadbeef",
        branch="feature-branch",
        conclusion=conclusion,
        repo="RiddimSoftware/epac",
    )


class FakeLinearClient:
    def __init__(self, existing: list[ci_failure_to_linear.OpenCIFailureIssue] | None = None) -> None:
        self.existing = existing or []
        self.created: list[ci_failure_to_linear.LinearIssueRequest] = []
        self.find_requests: list[dict[str, str]] = []
        self.comments: list[tuple[str, str]] = []
        self.description_updates: list[tuple[str, str]] = []

    def find_open_issue(
        self,
        *,
        team_key: str,
        label_name: str,
        title: str,
    ) -> list[ci_failure_to_linear.OpenCIFailureIssue]:
        self.find_requests.append({"team_key": team_key, "label_name": label_name, "title": title})
        return self.existing

    def create_issue(self, issue: ci_failure_to_linear.LinearIssueRequest) -> dict[str, str]:
        self.created.append(issue)
        return {"identifier": "EPAC-999", "url": "https://linear.app/riddimsoftware/issue/EPAC-999"}

    def add_comment(self, issue_id: str, body: str) -> dict[str, str]:
        self.comments.append((issue_id, body))
        return {"id": "comment-1", "url": "https://linear.app/comment/comment-1"}

    def update_issue_description(self, issue_id: str, description: str) -> None:
        self.description_updates.append((issue_id, description))


def test_no_existing_issue_creates_expected_linear_issue_request() -> None:
    client = FakeLinearClient()

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome(),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    assert created == {"identifier": "EPAC-999", "url": "https://linear.app/riddimsoftware/issue/EPAC-999"}
    assert client.find_requests == [
        {
            "team_key": "EPAC",
            "label_name": "ci-failure",
            "title": "[CI] Backend PR failing on feature-branch",
        }
    ]
    assert client.created == [
        ci_failure_to_linear.LinearIssueRequest(
            title="[CI] Backend PR failing on feature-branch",
            description="\n".join(
                [
                    "<!-- ci-failure-handler:comment-count:0 -->",
                    "",
                    "Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
                    "Head SHA: `abc12345`",
                ]
            ),
            priority=1,
            state="Todo",
            team_key="EPAC",
            label_names=("ci-failure",),
        )
    ]
    assert client.comments == []
    assert client.description_updates == []


def test_existing_open_issue_adds_comment_and_increments_counter() -> None:
    client = FakeLinearClient(
        [
            ci_failure_to_linear.OpenCIFailureIssue(
                id="issue-1",
                title="[CI] Backend PR failing on feature-branch",
                description="<!-- ci-failure-handler:comment-count:2 -->\n\nFailed run: old",
                updated_at="2026-05-25T10:00:00.000Z",
            )
        ]
    )

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome(),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    assert created is None
    assert client.created == []
    assert client.comments == [
        (
            "issue-1",
            "\n".join(
                [
                    "Additional failure detected for this workflow.",
                    "",
                    "- Run: https://github.com/RiddimSoftware/epac/actions/runs/123",
                    "- Head SHA: `abc12345`",
                    "- Attempt count: 3",
                ]
            ),
        )
    ]
    assert client.description_updates == [
        (
            "issue-1",
            "<!-- ci-failure-handler:comment-count:3 -->\n\nFailed run: old",
        )
    ]


def test_existing_open_issue_at_comment_cap_exits_zero_without_comment(capsys) -> None:
    for handler in ci_failure_to_linear.logger.handlers:
        if hasattr(handler, "stream"):
            handler.stream = sys.stderr
    client = FakeLinearClient(
        [
            ci_failure_to_linear.OpenCIFailureIssue(
                id="issue-1",
                title="[CI] Backend PR failing on feature-branch",
                description="<!-- ci-failure-handler:comment-count:5 -->\n\nFailed run: old",
                updated_at="2026-05-25T10:00:00.000Z",
            )
        ]
    )

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome(),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    captured = capsys.readouterr()
    assert created is None
    assert client.created == []
    assert client.comments == []
    assert client.description_updates == []
    assert "CI failure comment cap reached" in captured.err


def test_two_matching_open_issues_comments_on_most_recently_updated_and_warns(capsys) -> None:
    for handler in ci_failure_to_linear.logger.handlers:
        if hasattr(handler, "stream"):
            handler.stream = sys.stderr
    client = FakeLinearClient(
        [
            ci_failure_to_linear.OpenCIFailureIssue(
                id="older-issue",
                title="[CI] Backend PR failing on feature-branch",
                description="<!-- ci-failure-handler:comment-count:1 -->",
                updated_at="2026-05-25T10:00:00.000Z",
            ),
            ci_failure_to_linear.OpenCIFailureIssue(
                id="newer-issue",
                title="[CI] Backend PR failing on feature-branch",
                description="<!-- ci-failure-handler:comment-count:4 -->",
                updated_at="2026-05-25T11:00:00.000Z",
            ),
        ]
    )

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome(),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    captured = capsys.readouterr()
    assert created is None
    assert client.created == []
    assert client.comments[0][0] == "newer-issue"
    assert "- Attempt count: 5" in client.comments[0][1]
    assert client.description_updates == [
        ("newer-issue", "<!-- ci-failure-handler:comment-count:5 -->")
    ]
    assert "multiple open CI failure issues matched" in captured.err


def test_success_path_is_noop() -> None:
    client = FakeLinearClient()

    created = ci_failure_to_linear.report_ci_workflow_outcome(
        outcome("success"),
        client,  # type: ignore[arg-type]
        team_key="EPAC",
    )

    assert created is None
    assert client.created == []
    assert client.find_requests == []


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
        if "ResolveIssueLabel" in payload["query"]:
            return (
                200,
                json.dumps(
                    {
                        "data": {
                            "issueLabels": {
                                "nodes": [
                                    {"id": "label-ci-failure", "name": "ci-failure"}
                                ]
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
        title="[CI] Backend PR failing on branch",
        description="\n".join(
            [
                "<!-- ci-failure-handler:comment-count:0 -->",
                "",
                "Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
                "Head SHA: `abc12345`",
            ]
        ),
        priority=1,
        state="Todo",
        team_key="EPAC",
        label_names=("ci-failure",),
    )

    client.create_issue(issue)
    client.create_issue(issue)

    team_requests = [payload for payload in requests if "ResolveTeam" in payload["query"]]
    label_requests = [payload for payload in requests if "ResolveIssueLabel" in payload["query"]]
    issue_requests = [payload for payload in requests if "CreateCIWorkflowFailureIssue" in payload["query"]]
    assert len(team_requests) == 1
    assert len(label_requests) == 1
    assert len(issue_requests) == 2
    assert issue_requests[0]["variables"]["input"] == {
        "teamId": "team-123",
        "title": "[CI] Backend PR failing on branch",
        "description": "\n".join(
            [
                "<!-- ci-failure-handler:comment-count:0 -->",
                "",
                "Failed run: https://github.com/RiddimSoftware/epac/actions/runs/123",
                "Head SHA: `abc12345`",
            ]
        ),
        "priority": 1,
        "stateId": "state-todo",
        "labelIds": ["label-ci-failure"],
    }


def test_find_open_issue_uses_exact_linear_graphql_filter() -> None:
    requests: list[dict] = []

    def fake_transport(payload: dict, _headers: dict[str, str]) -> tuple[int, str]:
        requests.append(payload)
        return (
            200,
            json.dumps(
                {
                    "data": {
                        "issues": {
                            "nodes": [
                                {
                                    "id": "issue-1",
                                    "title": "[CI] Backend PR failing on main",
                                    "description": "<!-- ci-failure-handler:comment-count:0 -->",
                                    "updatedAt": "2026-05-25T10:00:00.000Z",
                                    "identifier": "EPAC-999",
                                    "url": "https://linear.example/EPAC-999",
                                }
                            ]
                        }
                    }
                }
            ),
        )

    client = ci_failure_to_linear.LinearClient("token", transport=fake_transport, sleep=lambda _seconds: None)

    issues = client.find_open_issue(
        team_key="EPAC",
        label_name="ci-failure",
        title="[CI] Backend PR failing on main",
    )

    assert issues == [
        ci_failure_to_linear.OpenCIFailureIssue(
            id="issue-1",
            title="[CI] Backend PR failing on main",
            description="<!-- ci-failure-handler:comment-count:0 -->",
            updated_at="2026-05-25T10:00:00.000Z",
            identifier="EPAC-999",
            url="https://linear.example/EPAC-999",
        )
    ]
    assert requests[0]["variables"] == {
        "teamKey": "EPAC",
        "labelName": "ci-failure",
        "title": "[CI] Backend PR failing on main",
    }
    query = requests[0]["query"]
    assert 'team: { key: { eq: $teamKey } }' in query
    assert 'state: { type: { in: [unstarted, started] } }' in query
    assert 'labels: { name: { eq: $labelName } }' in query
    assert 'title: { eq: $title }' in query
