# Performance Budgets

Performance budget files live here so local harnesses and CI parse the same thresholds.

Use one text file per metric and platform:

```text
<metric-name>.sim.txt
<metric-name>.device.txt
```

Each file contains a single numeric budget in the metric's canonical unit. Current canonical units:

| Metric | Unit |
| --- | --- |
| `launch-time-seconds` | seconds |
| `memory-physical-kb` | peak physical memory in kilobytes |

`scripts/ci/perf_parse.py` treats `*.sim.txt` and `*.device.txt` files as the expected metric list for the selected platform and fails if the matching `.xcresult` contains no measurements for any expected metric.

Swift performance tests should use `PerfMeasurementGuard` to declare the expected metric names at the `measure` call site. XCTest only exposes per-metric sample counts in the `.xcresult`, so `perf_parse.py` is the runner-level assertion that prevents silently-green tests when a metric emits no measured line.

The unqualified `launch-time-seconds.txt` file is a legacy simulator budget consumed by `.github/workflows/perf-launch.yml`. Keep it in place until that workflow is migrated; its simulator equivalent is `launch-time-seconds.sim.txt`.
