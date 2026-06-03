# In-Process Simulator Performance Budgets

`make perf-sim` runs the in-process XCTest performance suite for SwiftData reads,
SwiftData migration open, and Hansard XML parsing. The result-bundle guard in
`scripts/perf/check_in_process_metrics.py` fails if any expected metric is
missing or exceeds the budget files under `.github/perf-budgets/in-process-sim/`.

Simulator CPU measurements are host-Mac measurements. Treat them as directional
relative-regression signals for the same runner class, not as device absolutes.
