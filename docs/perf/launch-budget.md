# Launch Budget Ratchet

Project context: [Cold-launch performance: from 7.4s toward 5s](https://linear.app/riddimsoftware/project/cold-launch-performance-from-74s-toward-5s-53dadbf814ea).

## Budget Location

The cold-launch budget lives at `.github/perf-budgets/launch-time-seconds.txt`.

The file intentionally contains only the numeric budget so CI can read it directly with `cat`.

## Workflow

The manual `.github/workflows/perf-launch.yml` workflow runs `epacUITests/epacUITestsLaunchTests/testLaunchPerformance` on GitHub-hosted `macos-latest`, using the latest available iOS 26.x Simulator runtime and an `iPhone 17 Pro Max` when that device is available.

After `xcodebuild` finishes, the workflow extracts the reported `average:` launch metric, compares it to `.github/perf-budgets/launch-time-seconds.txt`, and writes the budget, measured average, simulator, runtime, and pass/fail result to the GitHub Actions step summary. The workflow fails when the measured average is greater than the budget. It uploads `LaunchPerf.xcresult` as an artifact on both passing and failing runs for offline inspection.

## Ratchet Protocol

Humans may only edit `.github/perf-budgets/launch-time-seconds.txt` through a pull request.

Hard rule: the autonomous-developer loop must never edit `.github/perf-budgets/launch-time-seconds.txt`.

Ratchet the budget down only after the current budget has been met cleanly across at least 3 consecutive `workflow_dispatch` runs on `main`.

Use the PR title convention `[perf] ratchet launch budget from X.Xs to Y.Ys`.

## macos-latest GHA Baseline

## macos-latest GHA Baseline (2026-05-26)

- Verdict: **Blocked**
- Evidence date: 2026-05-26
- Runner image: `macos-15-arm64` (release `20260520.0085`)
- Simulator target: `iPhone 17 Pro Max` (`iOS 26.2` runtime) on all dispatches.
- Root cause: `evidence` package compile fails before the launch metric is emitted (`'open' is only available in iOS 16.4 or newer`), so measured averages could not be captured from run summaries/xcresult artifacts.

| Dispatch run | Status | Duration (s) | Result | Note |
| --- | --- | ---: | --- | --- |
| [26465778375](https://github.com/RiddimSoftware/epac/actions/runs/26465778375) | failure | 119 | blocked | Compile error in `EvidenceApplication.swift` before test metrics |
| [26465775282](https://github.com/RiddimSoftware/epac/actions/runs/26465775282) | failure | 199 | blocked | Compile error in `EvidenceApplication.swift` before test metrics |
| [26465772478](https://github.com/RiddimSoftware/epac/actions/runs/26465772478) | failure | 136 | blocked | Compile error in `EvidenceApplication.swift` before test metrics |

Because no run reached step-summary emission of `Measured average`, no numeric mean/min/max/relative-stdev could be computed for this spike run.
