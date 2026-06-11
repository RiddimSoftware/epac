from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "data-ingestion.yml"
LEGACY_WORKFLOWS = [
    REPO_ROOT / ".github" / "workflows" / "hansard-search-reindex.yml",
    REPO_ROOT / ".github" / "workflows" / "lobbying-reindex.yml",
]

EXPECTED_PIPELINE_TOGGLES = {
    "run_search",
    "run_lobbying",
    "run_bills",
    "run_bills_indexer",
    "run_members",
    "run_members_indexer",
    "run_votes",
}

EXPECTED_LEGACY_CRONS = {
    "0 12 * * *",
    "0 3 * * *",
    "0 12 * * 1",
    "0 12 1 */3 *",
}


def load_workflow() -> dict:
    assert WORKFLOW_PATH.exists(), f"missing workflow: {WORKFLOW_PATH}"
    workflow = yaml.load(WORKFLOW_PATH.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    assert isinstance(workflow, dict), "workflow YAML must parse to a mapping"
    return workflow


def test_data_ingestion_workflow_replaces_legacy_workflows() -> None:
    assert WORKFLOW_PATH.exists()
    for legacy_workflow in LEGACY_WORKFLOWS:
        assert not legacy_workflow.exists(), f"legacy workflow still exists: {legacy_workflow}"


def test_data_ingestion_workflow_has_manual_pipeline_toggles() -> None:
    workflow = load_workflow()

    assert workflow.get("name") == "Data Ingestion"
    triggers = workflow.get("on")
    assert isinstance(triggers, dict), "workflow must declare GitHub Actions triggers"

    workflow_dispatch = triggers.get("workflow_dispatch")
    assert isinstance(workflow_dispatch, dict), "workflow must be manually runnable"
    inputs = workflow_dispatch.get("inputs")
    assert isinstance(inputs, dict), "workflow_dispatch must expose inputs"

    environment = inputs.get("environment")
    assert isinstance(environment, dict), "workflow_dispatch must choose environment"
    assert environment.get("type") == "choice"
    assert environment.get("required") == "true"
    assert environment.get("options") == ["staging", "production"]

    missing_toggles = EXPECTED_PIPELINE_TOGGLES.difference(inputs)
    assert not missing_toggles, "missing toggles: " + ", ".join(sorted(missing_toggles))

    for input_name in sorted(EXPECTED_PIPELINE_TOGGLES):
        toggle = inputs[input_name]
        assert isinstance(toggle, dict), f"{input_name} must be a dispatch input"
        assert toggle.get("type") == "boolean", f"{input_name} must be boolean"
        assert toggle.get("required") == "true", f"{input_name} must be required"
        assert toggle.get("default") == "false", f"{input_name} must default off"


def test_data_ingestion_workflow_preserves_legacy_schedules() -> None:
    workflow = load_workflow()

    triggers = workflow["on"]
    schedules = triggers.get("schedule")
    assert isinstance(schedules, list), "workflow must define cron schedules"
    crons = {entry.get("cron") for entry in schedules if isinstance(entry, dict)}
    assert crons == EXPECTED_LEGACY_CRONS


def test_data_ingestion_workflow_runs_selected_ingestors_with_matrix() -> None:
    workflow = load_workflow()

    jobs = workflow.get("jobs")
    assert isinstance(jobs, dict), "workflow must define jobs"

    plan = jobs.get("plan")
    assert isinstance(plan, dict), "workflow must build a selected-ingestor plan"
    plan_script = plan["steps"][0]["run"]
    for ingestor in [
        "search",
        "lobbying",
        "bills",
        "bills-indexer",
        "members",
        "members-indexer",
        "votes",
    ]:
        assert f'"{ingestor}"' in plan_script

    ingest = jobs.get("ingest")
    assert isinstance(ingest, dict), "workflow must define an ingestion job"
    strategy = ingest.get("strategy")
    assert isinstance(strategy, dict), "ingestion job must use a matrix strategy"
    assert "fromJson(needs.plan.outputs.matrix)" in strategy.get("matrix", "")

    env = ingest.get("env")
    assert isinstance(env, dict), "ingestion job must define shared env"
    assert env["BILLS_INDEX_PREFIX"] == "${{ vars.EPAC_BILLS_INDEX_PREFIX || 'bills/v1' }}"
    assert env["MEMBERS_INDEX_PREFIX"] == "${{ vars.EPAC_MEMBERS_INDEX_PREFIX || 'members/v1' }}"

    run_step = next(step for step in ingest["steps"] if step.get("name") == "Run ingestor")
    run_script = run_step["run"]
    assert "backend/hansard-search-index && go run ." in run_script
    assert "backend/lobbying-index && go run ." in run_script
    assert "aws s3 sync" in run_script
    assert 'backend/bills-indexer && DB_PATH="$RUNNER_TEMP/bills.db" go run .' in run_script
    assert 'backend/members-indexer && DB_PATH="$RUNNER_TEMP/members.db" go run .' in run_script
