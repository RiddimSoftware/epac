#!/usr/bin/env python3
"""
Find PR numbers merged between the previous successful TestFlight build and the
current workflow run's head SHA.

Compares the current workflow run's head SHA against the head SHA of the most
recent prior successful run of the "TestFlight Build" workflow, then lists all
merge commits in that range and extracts their PR numbers.

Writes a space-separated list of PR numbers to the GitHub Actions output variable
``pr_numbers``. Writes an empty string when there are no PRs (graceful no-op).

Usage (in GitHub Actions):
  python3 scripts/release/find_prs_since_previous_tf_build.py

Environment variables expected in GitHub Actions context:
  GITHUB_OUTPUT         - path to the step output file
  GITHUB_REPOSITORY     - owner/repo (e.g. RiddimSoftware/epac)
  GITHUB_RUN_ID         - current workflow run ID (skipped when searching prev)
  GITHUB_TOKEN          - token for `gh api` calls
"""
import os
import re
import subprocess
import sys


WORKFLOW_NAME = "TestFlight Build"


def gh_api(path: str, *, paginate: bool = False) -> str:
    cmd = ["gh", "api"]
    if paginate:
        cmd.append("--paginate")
    cmd.append(path)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"gh api error for {path}: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def git(*args: str) -> str:
    result = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    if result.returncode != 0:
        print(f"git error: {result.stderr}", file=sys.stderr)
        return ""
    return result.stdout.strip()


def get_previous_successful_head_sha(repo: str, current_run_id: str) -> str | None:
    import json

    page = 1
    while True:
        path = (
            f"repos/{repo}/actions/workflows"
            f"?per_page=100"
        )
        workflows_json = gh_api(path)
        try:
            data = json.loads(workflows_json)
        except json.JSONDecodeError:
            return None

        tf_workflow_id = None
        for wf in data.get("workflows", []):
            if wf.get("name") == WORKFLOW_NAME:
                tf_workflow_id = wf["id"]
                break

        if "workflows" not in data or len(data["workflows"]) < 100:
            break
        page += 1

    if tf_workflow_id is None:
        print(f"Workflow '{WORKFLOW_NAME}' not found in {repo}", file=sys.stderr)
        return None

    runs_path = (
        f"repos/{repo}/actions/workflows/{tf_workflow_id}/runs"
        f"?status=success&per_page=10"
    )
    runs_json = gh_api(runs_path)
    try:
        runs_data = json.loads(runs_json)
    except json.JSONDecodeError:
        return None

    for run in runs_data.get("workflow_runs", []):
        if str(run.get("id")) == current_run_id:
            continue
        head_sha = run.get("head_sha")
        if head_sha:
            return head_sha

    return None


def get_current_head_sha() -> str:
    return git("rev-parse", "HEAD")


def get_pr_numbers_in_range(base_sha: str | None, head_sha: str) -> list[str]:
    if base_sha:
        log = git("log", f"{base_sha}..{head_sha}", "--oneline", "--merges")
    else:
        log = git("log", head_sha, "--oneline", "--merges", "-30")

    pr_numbers: list[str] = []
    for line in log.splitlines():
        match = re.search(r"\(#(\d+)\)", line)
        if match:
            pr_numbers.append(match.group(1))
    return pr_numbers


def set_github_output(name: str, value: str) -> None:
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            f.write(f"{name}={value}\n")
    else:
        print(f"GITHUB_OUTPUT not set; would write: {name}={value}", file=sys.stderr)


def main() -> None:
    repo = os.environ.get("GITHUB_REPOSITORY", "RiddimSoftware/epac")
    current_run_id = os.environ.get("GITHUB_RUN_ID", "")

    current_sha = get_current_head_sha()
    prev_sha = get_previous_successful_head_sha(repo, current_run_id)

    if prev_sha:
        print(f"Previous successful TF build SHA: {prev_sha}", file=sys.stderr)
    else:
        print("No previous successful TF build found; scanning recent history.", file=sys.stderr)

    pr_numbers = get_pr_numbers_in_range(prev_sha, current_sha)
    pr_list = " ".join(pr_numbers)

    print(f"Found {len(pr_numbers)} PR(s): {pr_list or '(none)'}", file=sys.stderr)
    set_github_output("pr_numbers", pr_list)


if __name__ == "__main__":
    main()
