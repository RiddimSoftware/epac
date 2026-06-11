from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT = REPO_ROOT / "scripts" / "ci" / "run_native_indexer.py"


@pytest.mark.parametrize(
    ("pipeline", "extra_args", "expected_manifest_fields"),
    [
        (
            "hansard-search-index",
            ["--parliament-number", "45", "--session-number", "1"],
            {
                "version": "string",
                "built_at": "rfc3339",
                "parliament_number": "integer",
                "session_number": "integer",
                "sitting_count": "integer",
                "intervention_count": "integer",
                "message_count": "integer",
                "sqlite_key": "string",
                "sqlite_size_bytes": "integer",
                "sqlite_sha256": "sha256",
            },
        ),
        (
            "lobbying-index",
            [],
            {
                "version": "string",
                "built_at": "rfc3339",
                "sqlite_key": "string",
                "sqlite_size_bytes": "integer",
                "sqlite_sha256": "sha256",
                "table_counts": "object[string,integer]",
            },
        ),
        (
            "bills-indexer",
            ["--parliament-number", "45", "--session-number", "1"],
            {
                "version": "string",
                "built_at": "rfc3339",
                "parliament_number": "integer",
                "session_number": "integer",
                "sqlite_key": "string",
                "sqlite_size_bytes": "integer",
                "sqlite_sha256": "sha256",
                "table_counts": "object[string,integer]",
            },
        ),
        (
            "members-indexer",
            [],
            {
                "version": "string",
                "built_at": "rfc3339",
                "sqlite_key": "string",
                "sqlite_size_bytes": "integer",
                "sqlite_sha256": "sha256",
                "table_counts": "object[string,integer]",
            },
        ),
    ],
)
def test_native_indexer_cli_dry_run_reports_expected_output_formats(
    tmp_path: Path,
    pipeline: str,
    extra_args: list[str],
    expected_manifest_fields: dict[str, str],
) -> None:
    summary_path = tmp_path / "github-step-summary.md"
    env = os.environ.copy()
    env["GITHUB_STEP_SUMMARY"] = str(summary_path)

    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            pipeline,
            "--environment",
            "staging",
            "--dry-run",
            "--format",
            "json",
            *extra_args,
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, (
        f"{SCRIPT.relative_to(REPO_ROOT)} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

    payload = json.loads(result.stdout)
    assert payload["pipeline"] == pipeline
    assert payload["environment"] == "staging"
    assert payload["mode"] == "dry-run"
    assert payload["status"] == "planned"
    assert payload["summary_markdown_path"] == str(summary_path)
    assert payload["manifest_format"] == expected_manifest_fields

    commands = payload["commands"]
    assert isinstance(commands, list) and commands
    for command in commands:
        assert command["working_directory"].startswith("backend/")
        assert command["argv"][0] in {"go", "bash", "python3"}

    summary = summary_path.read_text(encoding="utf-8")
    assert f"## {pipeline} native reindex" in summary
    assert "| Output | Format |" in summary
    for field_name, field_type in expected_manifest_fields.items():
        assert f"| manifest.{field_name} | {field_type} |" in summary
