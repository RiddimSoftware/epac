# Realistic Fresh-Install Performance Suite

Project context: [Performance measurement coverage — every XCTMetric, sim + device](https://linear.app/riddimsoftware/project/performance-measurement-coverage-every-xctmetric-sim-device-c32fa64450c7). Issue: [EPAC-2205](https://linear.app/riddimsoftware/issue/EPAC-2205/add-a-fresh-install-live-network-realistic-perf-suite).

## What it is

`ios/epacUITests/Performance/FreshInstallPerfTests.swift` is the **realistic** performance
archetype: a true fresh install (`-UI_TEST_FRESH_STATE`, no evidence seed) that walks the
real onboarding flow and then makes **live** backend calls when opening a debate. It extends
the deterministic golden-path CUJ ([EPAC-2143](https://linear.app/riddimsoftware/issue/EPAC-2143/add-deterministic-golden-path-cuj-test-cold-launch-onboarding-to-first),
`OnboardingAndFirstDebateUITests`) with live network plus performance instrumentation.

## What it measures

| Signal | Instrument | Window |
| --- | --- | --- |
| Cold launch | `XCTApplicationLaunchMetric` | Fresh-install launch (`test_coldLaunch_freshInstall_perf`) |
| Onboarding traversal time | wall-clock attachment + `os_signpost` interval `onboardingTraversal` | welcome → postal code → MP confirm → topics |
| Debate-load latency | `XCTClockMetric` + `os_signpost` interval `fetchTranscript` | navigate → `debate-content` loaded (real `fetchTranscript`) |

Signposts use subsystem `com.riddimsoftware.epac.perf`, category `FreshInstallPerf`, so the
device-nightly Instruments/MetricKit context can pick up the on-device hitch + interval data.
The debate-load `measure` runs a single iteration (`iterationCount = 1`) because the
transcript is one-shot — a second iteration would be an in-memory cache hit, not a live fetch.

## Not a PR gate

Real-backend latency is non-deterministic, so this suite is a **nightly trend signal, not a
merge gate**. Two independent guards keep it off the PR gate:

1. **No PR workflow runs the `epacUITests` target.** `pr-build.yml` only builds; the golden-path
   CUJ workflow pins `-only-testing:.../OnboardingAndFirstDebateUITests`. A new UI-test class is
   therefore excluded from the PR gate by construction.
2. **Runtime opt-in.** Every test skips (`XCTSkip`) unless `EPAC_PERF_NIGHTLY=1` is present in the
   process environment. Only the nightly/device runner sets it. Absent it the suite skips cleanly
   and makes **no** live network calls — so it is safe even if the full UI-test target is run
   locally or in some future broad CI sweep.

CI scheduling itself (the gate boundaries and the device-nightly schedule that exports
`EPAC_PERF_NIGHTLY=1`) is wired by separate issues in the project and is out of scope here.

## Soft-fail on network errors

Because the backend is real, transient failures must not turn the suite red:

- If the live sitting-calendar load never yields a sitting day → `XCTSkip` with the timeout.
- If the live `fetchTranscript` never renders `debate-content` → `XCTSkip` with the timeout.

A skip is a non-event for the merge queue and shows up as "did not sample this run" in the
nightly trend rather than a hard failure.

## Caveats

- **In-memory store.** Under XCTest the SwiftData store is in-memory, so this *simulates* a fresh
  install — it exercises onboarding + the live fetch but **not** the on-disk first-run / migration
  path. On-device, the human-handoff owner confirms the suite reflects the true first-run feel.
- **Read-only network.** Calls hit production (Release config resolves the production backend).
  Keep the flow read-only.

## Running it locally

```bash
EPAC_PERF_NIGHTLY=1 xcodebuild test \
  -project ios/epac.xcodeproj \
  -scheme epac \
  -configuration Release \
  -destination "id=<simulator-or-device-udid>" \
  -only-testing:epacUITests/FreshInstallPerfTests
```

Omit `EPAC_PERF_NIGHTLY` and every test reports as skipped — that is the default, gate-safe state.

## Related

- Launch budget ratchet: [`launch-budget.md`](launch-budget.md)
- Golden-path CUJ workflow: `.github/workflows/golden-path-cuj.yml`
- PR gate: `.github/workflows/pr-build.yml`
