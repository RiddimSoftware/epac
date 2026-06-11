#!/usr/bin/env python3
"""Contract tests for the master data-ingestion GitHub Actions workflow."""

from __future__ import annotations

from pathlib import Path


WORKFLOW_PATH = Path(".github/workflows/data-ingestion.yml")

EXPECTED_PIPELINE_TOGGLES = {
    "run_cabinet",
    "run_corrections_statistics",
    "run_cpi_statistics",
    "run_cpp_oas_statistics",
    "run_ei_statistics",
    "run_fiscal_monitor",
    "run_lobbying",
    "run_pbo",
    "run_student_finance_statistics",
    "run_transport_safety_statistics",
    "run_vac_statistics",
}


def load_github_actions_workflow() -> dict:
    assert WORKFLOW_PATH.exists(), (
        "Expected a master data-ingestion workflow at "
        f"{WORKFLOW_PATH.as_posix()}"
    )

    import yaml

    workflow_text = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.load(workflow_text, Loader=yaml.BaseLoader)
    assert isinstance(workflow, dict), "workflow YAML must parse to a mapping"
    return workflow


def test_data_ingestion_workflow_has_manual_pipeline_toggles() -> None:
    workflow = load_github_actions_workflow()

    assert workflow.get("name") == "Data Ingestion"

    triggers = workflow.get("on")
    assert isinstance(triggers, dict), "workflow must declare GitHub Actions triggers"

    workflow_dispatch = triggers.get("workflow_dispatch")
    assert isinstance(workflow_dispatch, dict), (
        "data ingestion must be manually runnable with workflow_dispatch"
    )

    inputs = workflow_dispatch.get("inputs")
    assert isinstance(inputs, dict), "workflow_dispatch must expose run toggles"

    environment = inputs.get("environment")
    assert isinstance(environment, dict), "workflow_dispatch must choose environment"
    assert environment.get("type") == "choice"
    assert environment.get("required") == "true"
    assert environment.get("options") == ["staging", "production"]

    missing_toggles = EXPECTED_PIPELINE_TOGGLES.difference(inputs)
    assert not missing_toggles, (
        "workflow_dispatch is missing pipeline toggles: "
        + ", ".join(sorted(missing_toggles))
    )

    for input_name in sorted(EXPECTED_PIPELINE_TOGGLES):
        toggle = inputs[input_name]
        assert isinstance(toggle, dict), f"{input_name} must be a dispatch input"
        assert toggle.get("type") == "boolean", f"{input_name} must be boolean"
        assert toggle.get("required") == "true", f"{input_name} must be required"
        assert toggle.get("default") == "false", f"{input_name} must default off"
