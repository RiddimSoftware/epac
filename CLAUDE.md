# epac — Engineering Guide

epac is an iOS civic-engagement app showing Canada's House of Commons Hansard debates in a group-chat format. Stack: SwiftUI + SwiftData (iOS 17+), Python backend (Lambdas + SQLite FTS5 in S3), static website. The Linear team is **EPAC** and all work for this repo lives there.

Deeper context lives in `docs/`:

- Brand and copy: `docs/brand/brand-brief-v1.md`
- Architecture decisions: `docs/architecture/` (Navigation, SwiftData migration, Search index, Parsed speech schema, Live status, Bilingual search, …)
- Backend API spec: `backend/openapi/openapi.json` — adding or changing an endpoint requires updating the spec in the same PR
- Factory + intake: `docs/factory/`
- Design system: `docs/design/`

## How to use this file

This file is the rules-and-pointers map for agents and contributors. Detailed rationale lives in `docs/architecture/`, `docs/factory/`, and adjacent subsystem docs. Update this file when a **rule** changes; update the linked docs when the **rationale** changes.

## Intake harness — start here for any fix or feature

Bug fixes, feature requests, fact-check questions, and open-data corrections all start with a **validated SPEC** under `.factory/intake/`. If a user or LLM session asks for one of those and no valid SPEC exists yet, do not edit app, backend, website, workflow, or release code. Run intake first:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

The SPEC must include observed behavior, expected behavior, reproduction steps, acceptance criteria, evidence plan, validation plan, non-goals, and provenance.

Router skill, four-mode intake (bug / feature / fact-check / open-data), and codex/Claude hook wiring are described in `docs/factory/bugfix-intake.md` and `docs/factory/bugfix-intake-hooks.md`. The hooks are capture-only — they do not block tool calls. The honor-system rule above is the actual gate.

## iOS architecture rules

### MVVM with `@Observable` (EPAC-702)

ViewModels accept service dependencies via **protocol injection**. No singletons in ViewModels. Pass `ModelContext` and `Fetch` as method parameters; do not store them on the ViewModel. Define a protocol for session-scoped service state (`MemberResolving`, `SittingCalendarFetching`, …) and inject `any Protocol` so tests can mock without touching SwiftData. Domain models (`ParliamentMember`, `Sitting`, …) must not contain presentation-only properties.

### SwiftData schema changes

Any change to a SwiftData `@Model` requires a new `SchemaVN` enum and a new stage in `EpacMigrationPlan` (`ios/epac/Model/Migration.swift`). Existing `SchemaVN` enums are **immutable** once shipped. The container performs **destructive recovery on migration failure** as a fallback to the ladder — see `docs/architecture/swiftdata-schema-migration.md` for the full policy (ADR-003 supersedes ADR-002).

### Navigation

Five-tab structure: Home / Parliament / Members / Accountability / Search. New features must state their navigation home in the PR description. Full ADR: `docs/architecture/navigation-architecture-epac47.md`.

### Backend config

iOS never hardcodes backend hosts. Read `BackendConfig.shared.baseURL` (`ios/epac/Util/BackendConfig.swift`). Debug reads staging from `ios/Config/Debug.xcconfig`; Release reads production. To point a local run at another backend, set `BACKEND_BASE_URL` on the active Xcode scheme.

## Quality gates

### SwiftLint (EPAC-334)

`--strict` is the CI gate — warnings fail. Surprising rule: `cyclomatic_complexity` capped at **5**. Banned outright: `force_cast`, `force_try`, `empty_count`, `redundant_nil_coalescing`, `explicit_init`. Config: `.swiftlint.yml`. To break a rule, use `// swiftlint:disable:next <rule>` **with a one-line reason** (or a `disable / enable` block). Local: `swiftlint --fix` then `swiftlint --strict`.

### iOS coverage thresholds (EPAC-352, EPAC-625)

Enforced only for app modules **changed by the PR**. Workflow: `.github/workflows/ios-coverage.yml`. New ViewModel code must include unit tests in the same PR unless the description explains why the behavior is only testable through UI or integration coverage.

| Module | Min | Pattern |
|---|---:|---|
| ViewModels | 60% | `*ViewModel.swift`, `ViewModels/` |
| Services | 50% | `ios/epac/Util/*Service.swift`, `*Manager.swift` |
| Models | 40% | `ios/epac/Model/` |
| Views | 0% | `ios/epac/Views/` (XCUITest covers these) |

### Backend Python logging (EPAC-176)

Structured JSON to **stderr**, one object per record — never `print()`. Reserved fields: `timestamp` (UTC ISO-8601 with `Z`), `level`, `pipeline`, `message`. Pipeline-specific context goes through `extra={...}`. Every pipeline `main()` logs a `pipeline started` event, a `pipeline finished` event with `records_processed` and `duration_ms`, and at least one `error` event per handled failure (with `error`, `url`, `duration_ms`). Stdout is reserved for the script's JSON payload. Reference: `backend/cabinet/cabinet_ingest.py`.

### Backend API rate limits (EPAC-225)

Enforced via `observability.WrapAPIGateway` / `WrapAPIGatewayV2`. Keys prefer `X-Device-ID`, fall back to source IP / `X-Forwarded-For`. Limits: `/api/v1/` general **100/min**, `/api/v1/live` **2/min**, `/api/v1/members*` **10/min**, `/api/v1/calendar/house.ics` **1 per 5 min**. Limit hits return HTTP 429 with `Retry-After`; iOS `NetworkService` honors it within its four-attempt retry budget.

## Pull requests

GitHub auto-injects `.github/PULL_REQUEST_TEMPLATE.md` on `gh pr create`. Fill the Scope / Bugfix SPEC / Testing notes / Screenshots / Related issue sections.

### Author essentials

- Build passes (`cd ios && make build`).
- App runs (`cd ios && make simulator`).
- One logical change. Aim < 300 lines; > 400 needs written justification.
- Tests included or updated for testable changes.
- Screenshots for UI changes (before/after table in the description).
- `Resolves EPAC-N` in the description.
- **`Release-Note:` line if user-facing.** The daily release pipeline (`scripts/release/generate_release_notes.py`) collects these into `ios/fastlane/metadata/en-CA/release_notes.txt`. Omit only for CI, docs, infra, and refactor PRs with no visible user impact.

### Reviewer expectations

Prefix non-blocking findings with `nit:` or `optional:`. Approve if the approach is sound, even if you would have done it differently — leave a `nit:` for style. Never raise "why didn't you use X?" without explaining why X would be better *for this specific case*.

## Linear lifecycle

- **Picking up**: auto → **In Progress** on first push of a `claude/<id>` branch via Linear's GitHub integration. Set manually via `save_issue` if you claim before pushing.
- **PR opened**: Linear auto-links via the issue ID in branch / PR title / PR body. The developer also posts the PR URL as a Linear comment for human readability.
- **PR merged**: auto → **Done**.

Verify state matches reality at session boundaries — the integration is best-effort.

## Estimation

epac follows the org-wide estimation standard at `agent-config/context/linear-standards.md`. The Linear `Estimate` field measures **complexity** — how capable an implementer needs to be — not effort hours. The ladder is `1, 2, 4, 8, 16`. **Maximum is 16; anything larger must be split before pickup.** When in doubt, upgrade one tier rather than sandbagging to `8`.

| Estimate | Descriptor |
|---|---|
| 1 | Trivial — single-line / config / doc word swap |
| 2 | Simple — single-file change following an obvious pattern |
| 4 | Standard-low — well-scoped feature or bug fix in an existing module |
| 8 | Standard — multi-file feature, clear root-cause fix; some novel reasoning |
| 16 | Substantial — design choices required; if it feels bigger, split |

An issue cannot leave Backlog without this field set.

## Definition of Done

A ticket is Done when:

1. PR is merged to `main` via an approved review.
2. The app builds without warnings on the current Xcode release.
3. Relevant tests pass.
4. The Linear issue is transitioned to **Done** (auto via PR merge, or manually).
5. PR URL is posted as a Linear comment on the issue.

## Deep references

- Architecture ADRs: `docs/architecture/`
- Brand brief: `docs/brand/brand-brief-v1.md`
- Intake harness: `docs/factory/bugfix-intake.md`, `docs/factory/bugfix-intake-hooks.md`
- Backend OpenAPI: `backend/openapi/openapi.json`
- Org-wide agent config: `/Users/sunny/code/CLAUDE.md` (loaded automatically for any session under `/Users/sunny/code/`)
- Linear standards: `agent-config/context/linear-standards.md` (sibling repo, also at `https://github.com/RiddimSoftware/agent-config`)
