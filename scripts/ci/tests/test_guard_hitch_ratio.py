from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "guard_hitch_ratio.py"
SPEC = importlib.util.spec_from_file_location("guard_hitch_ratio", MODULE_PATH)
assert SPEC is not None
guard_hitch_ratio = importlib.util.module_from_spec(SPEC)
sys.modules["guard_hitch_ratio"] = guard_hitch_ratio
assert SPEC.loader is not None
SPEC.loader.exec_module(guard_hitch_ratio)


def write_log(tmp_path: Path, body: str) -> Path:
    log = tmp_path / "perf.log"
    log.write_text(body, encoding="utf-8")
    return log


def run(monkeypatch: pytest.MonkeyPatch, *argv: str) -> int:
    monkeypatch.setattr(sys, "argv", ["guard_hitch_ratio.py", *argv])
    return guard_hitch_ratio.main()


def test_missing_budget_with_measurements_records_baseline(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    log = write_log(tmp_path, "Hitch ratio average: 1.5 ms/s\n")
    budget = tmp_path / "hitch-ratio-ms-per-s.device.txt"

    exit_code = run(monkeypatch, "--log", str(log), "--budget", str(budget))

    assert exit_code == 0
    captured = capsys.readouterr()
    assert "Record baseline" in captured.out
    assert "1.5" in captured.out


def test_missing_budget_without_measurements_records_baseline(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    log = write_log(tmp_path, "no relevant lines here\n")
    budget = tmp_path / "hitch-ratio-ms-per-s.device.txt"

    exit_code = run(monkeypatch, "--log", str(log), "--budget", str(budget))

    assert exit_code == 0
    captured = capsys.readouterr()
    assert "Record baseline" in captured.out


def test_budget_present_within_budget_succeeds(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    log = write_log(tmp_path, "Hitch ratio average: 2.0 ms/s\n")
    budget = tmp_path / "budget.txt"
    budget.write_text("5\n", encoding="utf-8")

    exit_code = run(monkeypatch, "--log", str(log), "--budget", str(budget))

    assert exit_code == 0
    captured = capsys.readouterr()
    assert "Hitch-ratio guard passed" in captured.out


def test_budget_present_over_budget_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    log = write_log(tmp_path, "Hitch ratio average: 10.0 ms/s\n")
    budget = tmp_path / "budget.txt"
    budget.write_text("5\n", encoding="utf-8")

    exit_code = run(monkeypatch, "--log", str(log), "--budget", str(budget))

    assert exit_code == 1
    captured = capsys.readouterr()
    assert "exceeded" in captured.err


def test_budget_present_no_measurements_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    log = write_log(tmp_path, "no relevant lines here\n")
    budget = tmp_path / "budget.txt"
    budget.write_text("5\n", encoding="utf-8")

    exit_code = run(monkeypatch, "--log", str(log), "--budget", str(budget))

    assert exit_code == 1
    captured = capsys.readouterr()
    assert "Missing non-empty hitch-ratio measurement" in captured.err
