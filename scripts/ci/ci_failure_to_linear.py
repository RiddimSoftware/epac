#!/usr/bin/env python3
"""Report GitHub Actions workflow outcomes to Linear."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
import os
import re
import sys
import time
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LINEAR_GRAPHQL_URL = "https://api.linear.app/graphql"
PIPELINE_NAME = "ci_failure_to_linear"
RETRY_DELAYS_SECONDS = (1, 2, 4)
CI_FAILURE_LABEL = "ci-failure"
CI_FAILURE_COMMENT_LIMIT = 5
CI_FAILURE_COMMENT_COUNT_PATTERN = re.compile(
    r"<!--\s*ci-failure-handler:comment-count:(\d+)\s*-->"
)


class _JSONFormatter(logging.Formatter):
    _RESERVED = {
        "name",
        "msg",
        "args",
        "levelname",
        "levelno",
        "pathname",
        "filename",
        "module",
        "exc_info",
        "exc_text",
        "stack_info",
        "lineno",
        "funcName",
        "created",
        "msecs",
        "relativeCreated",
        "thread",
        "threadName",
        "processName",
        "process",
        "message",
        "taskName",
    }

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "level": record.levelname,
            "pipeline": getattr(record, "pipeline", PIPELINE_NAME),
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key in self._RESERVED or key in payload:
                continue
            payload[key] = value
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def _configure_logging() -> logging.Logger:
    logger = logging.getLogger(PIPELINE_NAME)
    if logger.handlers:
        return logger
    handler = logging.StreamHandler(stream=sys.stderr)
    handler.setFormatter(_JSONFormatter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


logger = _configure_logging()


@dataclass(frozen=True)
class CIWorkflowOutcome:
    workflow_name: str
    run_url: str
    head_sha: str
    branch: str
    conclusion: str
    repo: str


@dataclass(frozen=True)
class PRInfo:
    number: int
    title: str
    html_url: str


@dataclass(frozen=True)
class OriginatingContext:
    pr: PRInfo
    linear_id: str | None = None
    project_id: str | None = None


@dataclass(frozen=True)
class LinearIssueRequest:
    title: str
    description: str
    priority: int
    state: str
    team_key: str
    label_names: tuple[str, ...] = ()
    project_id: str | None = None


@dataclass(frozen=True)
class OpenCIFailureIssue:
    id: str
    title: str
    description: str
    updated_at: str
    identifier: str | None = None
    url: str | None = None


@dataclass(frozen=True)
class TeamResolution:
    team_id: str
    todo_state_id: str | None
    done_state_id: str | None


class GitHubPRClient:
    def __init__(self, token: str, *, base_url: str = "https://api.github.com") -> None:
        self._token = token
        self._base_url = base_url

    def find_pr_for_commit(self, repo: str, sha: str) -> PRInfo | None:
        url = f"{self._base_url}/repos/{repo}/commits/{sha}/pulls"
        request = Request(
            url,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Accept": "application/vnd.github+json",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                pulls = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            logger.warning(
                "GitHub PR lookup failed",
                extra={"error": str(exc), "sha": sha[:8], "repo": repo},
            )
            return None

        if not pulls:
            return None

        for pr in pulls:
            if pr.get("merge_commit_sha") == sha:
                return PRInfo(
                    number=pr["number"],
                    title=pr["title"],
                    html_url=pr["html_url"],
                )

        return PRInfo(
            number=pulls[0]["number"],
            title=pulls[0]["title"],
            html_url=pulls[0]["html_url"],
        )


def extract_linear_id(pr_title: str) -> str | None:
    match = re.search(r"\bEPAC-\d+\b", pr_title)
    return match.group(0) if match else None


class LinearAPIError(RuntimeError):
    def __init__(self, message: str, *, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


Transport = Callable[[dict[str, Any], dict[str, str]], tuple[int, str]]


class LinearClient:
    def __init__(
        self,
        api_token: str,
        *,
        endpoint: str = LINEAR_GRAPHQL_URL,
        transport: Transport | None = None,
        sleep: Callable[[int], None] = time.sleep,
    ) -> None:
        self.api_token = api_token
        self.endpoint = endpoint
        self._transport = transport or self._urlopen_transport
        self._sleep = sleep
        self._team_cache: dict[str, TeamResolution] = {}
        self._label_cache: dict[tuple[str, str], str] = {}

    def get_issue_project_id(self, identifier: str) -> str | None:
        query = """
        query GetIssueProjectId($id: String!) {
          issue(id: $id) {
            project {
              id
            }
          }
        }
        """
        data = self._graphql(query, {"id": identifier})
        issue = data.get("issue")
        if not issue:
            return None
        project = issue.get("project")
        if not project:
            return None
        return project.get("id")

    def create_issue(self, issue: LinearIssueRequest) -> dict[str, Any]:
        team = self.resolve_team(issue.team_key)
        input_payload: dict[str, Any] = {
            "teamId": team.team_id,
            "title": issue.title,
            "description": issue.description,
            "priority": issue.priority,
        }
        if team.todo_state_id:
            input_payload["stateId"] = team.todo_state_id
        if issue.project_id:
            input_payload["projectId"] = issue.project_id
        if issue.label_names:
            input_payload["labelIds"] = [
                self.resolve_issue_label_id(issue.team_key, label_name)
                for label_name in issue.label_names
            ]

        mutation = """
        mutation CreateCIWorkflowFailureIssue($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue {
              identifier
              url
            }
          }
        }
        """
        data = self._graphql(mutation, {"input": input_payload})
        payload = data.get("issueCreate") or {}
        if not payload.get("success"):
            raise LinearAPIError(f"Linear issueCreate did not succeed: {payload!r}")
        return payload.get("issue") or {}

    def find_open_issue(
        self,
        *,
        team_key: str,
        label_name: str,
        title: str,
    ) -> list[OpenCIFailureIssue]:
        query = """
        query FindOpenCIFailureIssues($teamKey: String!, $labelName: String!, $title: String!) {
          issues(
            filter: {
              team: { key: { eq: $teamKey } }
              state: { type: { in: ["unstarted", "started"] } }
              labels: { name: { eq: $labelName } }
              title: { eq: $title }
            }
            first: 20
          ) {
            nodes {
              id
              title
              description
              updatedAt
              identifier
              url
            }
          }
        }
        """
        data = self._graphql(query, {"teamKey": team_key, "labelName": label_name, "title": title})
        nodes = data.get("issues", {}).get("nodes", [])
        return [
            OpenCIFailureIssue(
                id=node["id"],
                title=node["title"],
                description=node.get("description") or "",
                updated_at=node.get("updatedAt") or "",
                identifier=node.get("identifier"),
                url=node.get("url"),
            )
            for node in nodes
        ]

    def add_comment(self, issue_id: str, body: str) -> dict[str, Any]:
        mutation = """
        mutation CreateCIWorkflowFailureComment($input: CommentCreateInput!) {
          commentCreate(input: $input) {
            success
            comment {
              id
              url
            }
          }
        }
        """
        data = self._graphql(mutation, {"input": {"issueId": issue_id, "body": body}})
        payload = data.get("commentCreate") or {}
        if not payload.get("success"):
            raise LinearAPIError(f"Linear commentCreate did not succeed: {payload!r}")
        return payload.get("comment") or {}

    def update_issue_description(self, issue_id: str, description: str) -> None:
        mutation = """
        mutation UpdateCIWorkflowFailureIssue($id: String!, $description: String!) {
          issueUpdate(id: $id, input: { description: $description }) {
            success
          }
        }
        """
        data = self._graphql(mutation, {"id": issue_id, "description": description})
        payload = data.get("issueUpdate") or {}
        if not payload.get("success"):
            raise LinearAPIError(f"Linear issueUpdate did not succeed: {payload!r}")

    def transition_issue_to_done(self, issue_id: str, done_state_id: str) -> None:
        mutation = """
        mutation TransitionCIWorkflowFailureIssue($id: String!, $stateId: String!) {
          issueUpdate(id: $id, input: { stateId: $stateId }) {
            success
          }
        }
        """
        data = self._graphql(mutation, {"id": issue_id, "stateId": done_state_id})
        payload = data.get("issueUpdate") or {}
        if not payload.get("success"):
            raise LinearAPIError(f"Linear issueUpdate (state transition) did not succeed: {payload!r}")

    def resolve_team(self, team_key: str) -> TeamResolution:
        if team_key in self._team_cache:
            return self._team_cache[team_key]

        query = """
        query ResolveTeam($key: String!) {
          teams(filter: { key: { eq: $key } }) {
            nodes {
              id
              states(first: 50) {
                nodes {
                  id
                  name
                  type
                }
              }
            }
          }
        }
        """
        data = self._graphql(query, {"key": team_key})
        nodes = data.get("teams", {}).get("nodes", [])
        if not nodes:
            raise LinearAPIError(f"Linear team not found for key: {team_key}")
        team = nodes[0]

        todo_state_id = _todo_state_id(team.get("states", {}).get("nodes", []))
        done_state_id = _done_state_id(team.get("states", {}).get("nodes", []))
        resolution = TeamResolution(team_id=team["id"], todo_state_id=todo_state_id, done_state_id=done_state_id)
        self._team_cache[team_key] = resolution
        return resolution

    def resolve_issue_label_id(self, team_key: str, label_name: str) -> str:
        cache_key = (team_key, label_name)
        if cache_key in self._label_cache:
            return self._label_cache[cache_key]

        query = """
        query ResolveIssueLabel($teamKey: String!, $labelName: String!) {
          issueLabels(
            filter: {
              team: { key: { eq: $teamKey } }
              name: { eq: $labelName }
            }
            first: 10
          ) {
            nodes {
              id
              name
            }
          }
        }
        """
        data = self._graphql(query, {"teamKey": team_key, "labelName": label_name})
        nodes = data.get("issueLabels", {}).get("nodes", [])
        if not nodes:
            raise LinearAPIError(f"Linear label not found for team {team_key}: {label_name}")
        label_id = nodes[0]["id"]
        self._label_cache[cache_key] = label_id
        return label_id

    def _graphql(self, query: str, variables: dict[str, Any]) -> dict[str, Any]:
        payload = {"query": query, "variables": variables}
        status_code, body = self._request_with_retries(payload)
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as exc:
            raise LinearAPIError("Linear returned invalid JSON", status_code=status_code) from exc
        if parsed.get("errors"):
            raise LinearAPIError(f"Linear GraphQL error: {parsed['errors']}", status_code=status_code)
        return parsed.get("data") or {}

    def _request_with_retries(self, payload: dict[str, Any]) -> tuple[int, str]:
        headers = {
            "Authorization": self.api_token,
            "Content-Type": "application/json",
        }
        delays = list(RETRY_DELAYS_SECONDS)
        for attempt in range(len(delays) + 1):
            try:
                status_code, body = self._transport(payload, headers)
                if status_code == 401:
                    raise LinearAPIError(
                        "LINEAR_API_TOKEN may be rotated; check GitHub repo secrets",
                        status_code=status_code,
                    )
                if 400 <= status_code < 500:
                    raise LinearAPIError(
                        f"Linear API request failed with HTTP {status_code}: {body}",
                        status_code=status_code,
                    )
                if status_code >= 500:
                    if attempt < len(delays):
                        self._sleep(delays[attempt])
                        continue
                    raise LinearAPIError(
                        f"Linear API request failed after retries with HTTP {status_code}: {body}",
                        status_code=status_code,
                    )
                return status_code, body
            except (URLError, TimeoutError, OSError) as exc:
                if attempt < len(delays):
                    self._sleep(delays[attempt])
                    continue
                raise LinearAPIError(f"Linear API request failed after retries: {exc}") from exc
        raise LinearAPIError("Linear API request failed after retries")

    def _urlopen_transport(self, payload: dict[str, Any], headers: dict[str, str]) -> tuple[int, str]:
        request = Request(
            self.endpoint,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urlopen(request, timeout=30) as response:
                return response.status, response.read().decode("utf-8")
        except HTTPError as exc:
            return exc.code, exc.read().decode("utf-8", errors="replace")


def resolve_originating_context(
    outcome: CIWorkflowOutcome,
    github_client: GitHubPRClient | None,
    linear_client: LinearClient,
) -> OriginatingContext | None:
    if not github_client:
        return None

    pr = github_client.find_pr_for_commit(outcome.repo, outcome.head_sha)
    if not pr:
        return None

    linear_id = extract_linear_id(pr.title)
    if not linear_id:
        return OriginatingContext(pr=pr)

    try:
        project_id = linear_client.get_issue_project_id(linear_id)
    except LinearAPIError as exc:
        logger.warning(
            "Linear issue lookup failed for project inheritance",
            extra={"linear_id": linear_id, "error": str(exc)},
        )
        project_id = None

    return OriginatingContext(pr=pr, linear_id=linear_id, project_id=project_id)


def report_ci_workflow_outcome(
    outcome: CIWorkflowOutcome,
    linear_client: LinearClient,
    *,
    team_key: str,
    github_client: GitHubPRClient | None = None,
) -> dict[str, Any] | None:
    if outcome.conclusion == "success":
        title = ci_failure_issue_title(outcome)
        matching_issues = linear_client.find_open_issue(
            team_key=team_key,
            label_name=CI_FAILURE_LABEL,
            title=title,
        )
        if not matching_issues:
            logger.info(
                "workflow succeeded; no open CI issue to resolve",
                extra={
                    "workflow_name": outcome.workflow_name,
                    "repo": outcome.repo,
                    "head_sha": outcome.head_sha,
                },
            )
            return None
        
        team = linear_client.resolve_team(team_key)
        if not team.done_state_id:
            raise LinearAPIError(f"Linear 'Done' state not found for team: {team_key}")
        
        if len(matching_issues) > 1:
            logger.warning(
                "multiple open CI failure issues matched on success; resolving all",
                extra={
                    "title": title,
                    "match_count": len(matching_issues),
                },
            )
        
        for issue in matching_issues:
            linear_client.add_comment(
                issue.id,
                f"Resolved by [green run]({outcome.run_url}) at SHA `{outcome.head_sha[:8]}`."
            )
            linear_client.transition_issue_to_done(issue.id, team.done_state_id)
            logger.info(
                "resolved open CI failure issue",
                extra={
                    "issue_id": issue.id,
                    "run_url": outcome.run_url,
                    "head_sha": outcome.head_sha[:8],
                },
            )
        return None

    if outcome.conclusion != "failure":
        raise ValueError(f"Unsupported workflow conclusion: {outcome.conclusion}")

    title = ci_failure_issue_title(outcome)
    matching_issues = linear_client.find_open_issue(
        team_key=team_key,
        label_name=CI_FAILURE_LABEL,
        title=title,
    )
    if matching_issues:
        issue = _most_recently_updated_issue(matching_issues)
        if len(matching_issues) > 1:
            logger.warning(
                "multiple open CI failure issues matched; commenting on most recently updated",
                extra={
                    "title": title,
                    "match_count": len(matching_issues),
                    "selected_issue_id": issue.id,
                },
            )

        comment_count = ci_failure_comment_count(issue.description)
        if comment_count >= CI_FAILURE_COMMENT_LIMIT:
            logger.warning(
                "CI failure comment cap reached; leaving existing issue untouched",
                extra={
                    "issue_id": issue.id,
                    "title": title,
                    "comment_count": comment_count,
                    "run_url": outcome.run_url,
                    "head_sha": outcome.head_sha[:8],
                },
            )
            return None

        next_count = comment_count + 1
        linear_client.add_comment(issue.id, ci_failure_comment_body(outcome, next_count))
        linear_client.update_issue_description(
            issue.id,
            description_with_ci_failure_comment_count(issue.description, next_count),
        )
        return None

    originating = resolve_originating_context(outcome, github_client, linear_client)

    return linear_client.create_issue(
        LinearIssueRequest(
            title=title,
            description=initial_ci_failure_description(outcome, originating),
            priority=1,
            state="Todo",
            team_key=team_key,
            label_names=(CI_FAILURE_LABEL,),
            project_id=originating.project_id if originating else None,
        )
    )


def ci_failure_issue_title(outcome: CIWorkflowOutcome) -> str:
    return f"[CI] {outcome.workflow_name} failing on {outcome.branch}"


def initial_ci_failure_description(
    outcome: CIWorkflowOutcome,
    originating: OriginatingContext | None = None,
) -> str:
    lines = [
        "<!-- ci-failure-handler:comment-count:0 -->",
        "",
        f"Failed run: {outcome.run_url}",
        f"Head SHA: `{outcome.head_sha[:8]}`",
    ]
    if originating and originating.linear_id:
        lines.append("")
        lines.append(
            f"Triggered by [PR #{originating.pr.number}]({originating.pr.html_url})"
            f" ([{originating.linear_id}]"
            f"(linear://linear.app/riddimsoftware/issue/{originating.linear_id}))"
        )
    return "\n".join(lines)


def ci_failure_comment_body(outcome: CIWorkflowOutcome, attempt_count: int) -> str:
    return "\n".join(
        [
            "Additional failure detected for this workflow.",
            "",
            f"- Run: {outcome.run_url}",
            f"- Head SHA: `{outcome.head_sha[:8]}`",
            f"- Attempt count: {attempt_count}",
        ]
    )


def ci_failure_comment_count(description: str) -> int:
    match = CI_FAILURE_COMMENT_COUNT_PATTERN.search(description)
    if not match:
        return 0
    return int(match.group(1))


def description_with_ci_failure_comment_count(description: str, count: int) -> str:
    marker = f"<!-- ci-failure-handler:comment-count:{count} -->"
    if CI_FAILURE_COMMENT_COUNT_PATTERN.search(description):
        return CI_FAILURE_COMMENT_COUNT_PATTERN.sub(marker, description, count=1)
    if not description.strip():
        return marker
    return f"{description.rstrip()}\n\n{marker}"


def _most_recently_updated_issue(issues: list[OpenCIFailureIssue]) -> OpenCIFailureIssue:
    return max(issues, key=lambda issue: issue.updated_at)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stdin-json", action="store_true", help="Read workflow outcome fields from stdin JSON")
    parser.add_argument("--workflow-name")
    parser.add_argument("--run-url")
    parser.add_argument("--head-sha")
    parser.add_argument("--branch")
    parser.add_argument("--conclusion", choices=["failure", "success"])
    parser.add_argument("--repo")
    parser.add_argument("--team-key", default=os.environ.get("LINEAR_TEAM_KEY"))
    return parser.parse_args(argv)


def outcome_from_args(args: argparse.Namespace) -> CIWorkflowOutcome:
    if args.stdin_json:
        payload = json.loads(sys.stdin.read())
        return CIWorkflowOutcome(
            workflow_name=_required(payload, "workflow_name"),
            run_url=_required(payload, "run_url"),
            head_sha=_required(payload, "head_sha"),
            branch=_required(payload, "branch"),
            conclusion=_required(payload, "conclusion"),
            repo=_required(payload, "repo"),
        )

    missing = [
        flag
        for flag, value in {
            "--workflow-name": args.workflow_name,
            "--run-url": args.run_url,
            "--head-sha": args.head_sha,
            "--branch": args.branch,
            "--conclusion": args.conclusion,
            "--repo": args.repo,
        }.items()
        if not value
    ]
    if missing:
        raise ValueError(f"Missing required arguments: {', '.join(missing)}")
    if not args.team_key:
        raise ValueError("Missing required Linear team key: pass --team-key or set LINEAR_TEAM_KEY")

    return CIWorkflowOutcome(
        workflow_name=args.workflow_name,
        run_url=args.run_url,
        head_sha=args.head_sha,
        branch=args.branch,
        conclusion=args.conclusion,
        repo=args.repo,
    )


def _required(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"Missing required stdin JSON field: {key}")
    return value


def _todo_state_id(states: list[dict[str, Any]]) -> str | None:
    for state in states:
        if str(state.get("name", "")).lower() == "todo":
            return state.get("id")
    for state in states:
        if state.get("type") == "unstarted":
            return state.get("id")
    return None


def _done_state_id(states: list[dict[str, Any]]) -> str | None:
    for state in states:
        if str(state.get("name", "")) == "Done":
            return state.get("id")
    return None


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        outcome = outcome_from_args(args)
    except (ValueError, json.JSONDecodeError) as exc:
        logger.error("invalid input", extra={"error": str(exc)})
        return 2

    if not args.team_key:
        logger.error(
            "invalid input",
            extra={"error": "Missing required Linear team key: pass --team-key or set LINEAR_TEAM_KEY"},
        )
        return 2

    api_token = os.environ.get("LINEAR_API_TOKEN", "").strip()
    if not api_token:
        logger.error("LINEAR_API_TOKEN is required")
        return 1

    github_token = os.environ.get("GITHUB_TOKEN", "").strip()
    github_client = GitHubPRClient(github_token) if github_token else None

    try:
        issue = report_ci_workflow_outcome(
            outcome,
            LinearClient(api_token),
            team_key=args.team_key,
            github_client=github_client,
        )
    except (LinearAPIError, ValueError) as exc:
        logger.error("failed to report workflow outcome", extra={"error": str(exc)})
        return 1

    if issue:
        sys.stdout.write(json.dumps(issue, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
