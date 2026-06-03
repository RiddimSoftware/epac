from __future__ import annotations

import importlib.util
import math
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "perf_parse.py"
SPEC = importlib.util.spec_from_file_location("perf_parse", MODULE_PATH)
assert SPEC is not None
perf_parse = importlib.util.module_from_spec(SPEC)
sys.modules["perf_parse"] = perf_parse
assert SPEC.loader is not None
SPEC.loader.exec_module(perf_parse)


def sample_metrics():
    return [
        {
            "testIdentifier": "epacUITests/LaunchPerfTests/testLaunchAndMemoryBaseline()",
            "testRuns": [
                {
                    "metrics": [
                        {
                            "displayName": "Application Launch Duration",
                            "unitOfMeasurement": "s",
                            "measurements": [1.2, 1.4],
                        },
                        {
                            "displayName": "Peak Physical Memory",
                            "unitOfMeasurement": "MB",
                            "measurements": [70.0, 72.0],
                        },
                    ]
                }
            ],
        }
    ]


def test_collects_known_launch_and_memory_metrics():
    reports = perf_parse.collect_reports(
        sample_metrics(),
        ["launch-time-seconds", "memory-physical-kb"],
        budgets={"launch-time-seconds": 5.0, "memory-physical-kb": 94000.0},
    )

    by_name = {report.metric_name: report for report in reports}
    assert by_name["launch-time-seconds"].present
    assert math.isclose(by_name["launch-time-seconds"].average, 1.3)
    assert by_name["launch-time-seconds"].budget == 5.0
    assert perf_parse.budget_status(by_name["launch-time-seconds"]) == "passed"
    assert by_name["memory-physical-kb"].present
    assert by_name["memory-physical-kb"].average == 71000.0


def test_marks_missing_expected_metric():
    reports = perf_parse.collect_reports(sample_metrics(), ["unknown-metric"])

    assert len(reports) == 1
    assert reports[0].metric_name == "unknown-metric"
    assert not reports[0].present


def test_reads_platform_budget_convention(tmp_path):
    budget_dir = tmp_path / "perf-budgets"
    budget_dir.mkdir()
    (budget_dir / "launch-time-seconds.sim.txt").write_text("5.0", encoding="utf-8")
    (budget_dir / "launch-time-seconds.txt").write_text("5.0", encoding="utf-8")
    (budget_dir / "memory-physical-kb.device.txt").write_text("100000", encoding="utf-8")

    assert perf_parse.expected_metrics_from_budget_dir(budget_dir, "sim") == [
        "launch-time-seconds"
    ]
    assert perf_parse.expected_metrics_from_budget_dir(budget_dir, "device") == [
        "memory-physical-kb"
    ]

    assert perf_parse.read_metric_budgets(budget_dir, "sim") == {
        "launch-time-seconds": 5.0
    }


def test_budget_failures_report_exceeded_metric():
    reports = perf_parse.collect_reports(
        sample_metrics(),
        ["launch-time-seconds"],
        budgets={"launch-time-seconds": 1.0},
    )

    assert perf_parse.budget_status(reports[0]) == "failed"
    assert perf_parse.budget_failures(reports) == [
        "launch-time-seconds: average 1.3 s exceeded budget 1"
    ]


def test_summary_table_renders_budget_and_missing_status(tmp_path):
    reports = perf_parse.collect_reports(
        sample_metrics(),
        ["launch-time-seconds", "unknown-metric"],
        budgets={"launch-time-seconds": 5.0, "unknown-metric": 2.0},
    )
    summary_path = tmp_path / "summary.md"

    perf_parse.write_summary(summary_path, reports)

    summary = summary_path.read_text(encoding="utf-8")
    assert "| launch-time-seconds | 5 | 1.3 | s | 2 | passed |" in summary
    assert "| * | unknown-metric | 2 | missing | raw | 0 | missing |" in summary
