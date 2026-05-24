# `.evidence/` — Regression evidence plans

This directory holds JSON plans consumed by [RiddimSoftware/evidence](https://github.com/RiddimSoftware/evidence) — the org's iOS PR-change-evidence tool. Each plan describes a sequence of deterministic app actions whose before/after screenshots demonstrate that a PR's runtime behavior is what it claims to be.

## File naming

| Path | Purpose |
|---|---|
| `pr-<N>.json` | One-off plan tied to a specific PR. Lives alongside the PR; can be deleted after the PR ships if the routes it covers are absorbed into a permanent regression plan. |
| `regression-<area>.json` | Permanent regression plan for an area (e.g. `regression-deep-links.json`). Re-run on every relevant PR. |

PR-specific plans for refactor/quality work should be **promoted** to a `regression-<area>.json` plan once the route catalog they exercise stabilizes — that way future refactors in the same area get covered for free.

## Plan shape

Plans are JSON consumed by `evidence capture-pr`. See the [evidence README](https://github.com/RiddimSoftware/evidence#package-usage) for the full schema. Required fields for the simctl runner:

- `runner`: `"simctl"` (launch-only) or `"xctest"` (requires an `epacUITests` `EvidencePlanRunner` harness)
- `ios.project`, `ios.scheme`, `ios.bundle_id`, `ios.destination`
- `launch.arguments` / `launch.environment` — applied once when the app is installed and launched
- `steps[]` — flat sequence of `launch` / `wait` / `screenshot` / `openURL` / `startVideo` / `stopVideo`

The simctl runner launches the app **once per revision** and runs all steps against the running instance. State accumulates across steps (presented sheets stay, `selectedTab` persists). Order steps so that each screenshot is meaningful from the prior state, or document the sequential nature in the route catalog.

## Determinism contract

Every plan should set the deterministic launch hook so before/after are comparable:

```json
{
  "launch": {
    "arguments": ["--evidence-mode", "-UIAnimationsDisabled", "YES"],
    "environment": { "EPAC_EVIDENCE_MODE": "1" }
  }
}
```

`EPAC_EVIDENCE_MODE=1` (or `--evidence-mode`) triggers `AppEnvironment.isEvidenceCaptureMode` and gives:

- In-memory SwiftData store (no leftover state)
- Onboarding and MyMP setup sheets suppressed at launch
- `selectedTab` defaults to `.home`
- App-open registration / background-refresh tasks skipped

Routes that depend on populated SwiftData entities (`navigateToMember`, sitting/Hansard loaders) will silent-fail or show empty states in evidence mode — that is itself a deterministic before/after match, but the route's full visible result requires fixture seeding (not yet implemented).

## How runs are triggered

- **Local:** `evidence capture-pr --repo RiddimSoftware/epac --pr <N> --plan .evidence/pr-<N>.json --output docs/build-evidence/pr-<N>`
- **CI:** `.github/workflows/evidence-regression.yml`. Triggers on `workflow_dispatch` (manual SHAs + plan) or `pull_request` (auto base/head). Posts a PR comment with the report summary; uploads the full bundle as a workflow artifact.

## Where artifacts go

- `docs/build-evidence/pr-<N>/before/` and `…/after/` — captured screenshots
- `docs/build-evidence/pr-<N>/manifest.json` — machine-readable run record
- `docs/build-evidence/pr-<N>/report.md` — reviewer-oriented summary
