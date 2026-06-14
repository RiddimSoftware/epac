from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "backend-staging.yml"


def load_workflow() -> dict:
    workflow = yaml.load(WORKFLOW_PATH.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    assert isinstance(workflow, dict), "workflow YAML must parse to a mapping"
    return workflow


def test_backend_staging_bounds_aws_cli_retries_and_timeouts() -> None:
    workflow = load_workflow()

    env = workflow.get("env")
    assert isinstance(env, dict), "workflow must declare global environment"
    assert env.get("AWS_RETRY_MODE") == "standard"
    assert int(env.get("AWS_MAX_ATTEMPTS", "0")) >= 3
    assert 1 <= int(env.get("AWS_CLI_CONNECT_TIMEOUT", "0")) <= 15
    assert 10 <= int(env.get("AWS_CLI_READ_TIMEOUT", "0")) <= 120
