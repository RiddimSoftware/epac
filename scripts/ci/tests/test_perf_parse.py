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
    )

    by_name = {report.metric_name: report for report in reports}
    assert by_name["launch-time-seconds"].present
    assert math.isclose(by_name["launch-time-seconds"].average, 1.3)
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
