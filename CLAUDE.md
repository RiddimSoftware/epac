# epac Engineering Guide

## Project Overview

epac is an iOS civic-engagement app for Canada's House of Commons Hansard experience, with a SwiftUI + SwiftData iOS app, Python and Go backend services, static website assets, release metadata, and product documentation. Civic content shown to users must trace to authoritative source data; do not invent, summarize, or rewrite parliamentary content with generated text.

## Intake Harness

Bug fixes start with a validated SPEC. If a bug fix request has no valid SPEC yet, do not edit app, backend, website, workflow, or release code before running:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

Pointers: `.factory/prompts/bugfix-intake.md`, `.factory/templates/bugfix-SPEC.md`, and `docs/factory/bugfix-intake.md`. The SPEC must cover observed behavior, expected behavior, reproduction, acceptance criteria, evidence, validation, non-goals, and provenance.

## iOS Architecture

- MVVM uses `@Observable` for root views with meaningful state and actions. Leaf/display-only views should receive data from parents rather than gaining empty ViewModels.
- ViewModels accept service dependencies through protocol injection; no singleton services in ViewModels. See [EPAC-702](https://linear.app/riddimsoftware/issue/EPAC-702/viewmodel-dependency-injection-refactor-replace-singleton-services).
- Pass `ModelContext` and `Fetch` as method parameters rather than storing SwiftData environment objects on ViewModels.
- `@Query` stays in Views because SwiftData requires it there.
- Domain models such as `ParliamentMember` must stay free of presentation-only concepts.
- Navigation architecture lives in `docs/architecture/navigation-architecture-epac47.md`.

## SwiftData Schema

Any change to a SwiftData `@Model` requires a new `SchemaVN` enum and a migration stage in `EpacMigrationPlan`. Never edit an existing shipped schema enum. SwiftData migration policy lives in `docs/architecture/swiftdata-schema-migration.md`; versioned migrations are the preferred path and destructive-on-failure cache recovery is only a fallback.

## Backend Config

iOS backend services should read `BackendConfig.shared.baseURL` from `ios/epac/Util/BackendConfig.swift` rather than hardcoding API hosts. Debug defaults to staging via `ios/Config/Debug.xcconfig`; Release defaults to production via `ios/Config/Release.xcconfig`; valid HTTPS `BACKEND_BASE_URL` overrides are accepted for local runs and CI.

Adding or changing a backend endpoint requires updating `backend/openapi/openapi.json` in the same PR.

## SwiftLint

Swift sources under `ios/**/*.swift` run SwiftLint with `--strict`; warnings fail CI. Config lives in `.swiftlint.yml`; CI lives in `.github/workflows/swiftlint.yml`. Local commands:

```bash
brew install swiftlint
swiftlint --fix
swiftlint --strict
```

Use per-line `// swiftlint:disable:next <rule>` only with a short reason. Do not relax project defaults for one call site.

## iOS Coverage

The coverage workflow is `.github/workflows/ios-coverage.yml`; reporting is handled by `scripts/ci/ios_coverage_report.py`. Thresholds apply to changed app modules:

| Module | Minimum | Scope |
|---|---:|---|
| ViewModels | 60% | `*ViewModel.swift`, `Views/**/ViewModels/` |
| Services | 50% | `ios/epac/Util/*Service.swift`, `*Manager.swift` |
| Models | 40% | `ios/epac/Model/` |
| Views | 0% | SwiftUI views, covered through UI/XCUITest |

New ViewModel, service, manager, or model logic needs focused tests unless the PR explains why only UI or integration coverage can exercise it.

## Backend Operations

- Python ingest scripts under `backend/` emit structured JSON logs to stderr and reserve stdout for payloads. Use the formatter pattern in `backend/cabinet/cabinet_ingest.py` or the existing pipeline-local equivalent.
- Go API handlers using `observability.WrapAPIGateway` or `WrapAPIGatewayV2` inherit shared `/api/v1/` rate limiting from `backend/observability/ratelimit.go`; clients should honor `Retry-After`.
- Backend environment and deployment details live beside the workflows: `.github/workflows/deploy-staging.yml`, `.github/workflows/deploy-production.yml`, and `backend/openapi/openapi.json`.

## Pull Requests

Keep PRs focused on one logical change, ideally under 300 changed lines. Self-review before opening. Link the Linear issue in the title/body, include verification evidence, and use `.github/PULL_REQUEST_TEMPLATE.md` for required fields.

Every user-facing change needs a one-line `Release-Note:` in the PR body. Omit it only for docs, CI, infra, tests, and refactors with no visible user impact.

## Linear Lifecycle

- Branches and PR titles include the issue key, e.g. `[EPAC-2118]: ...`.
- Linear auto-links PRs when the issue key appears in the branch, title, or body.
- Developers post the PR URL as a Linear comment after opening the PR.
- PR merge transitions the issue to Done through the Linear integration; verify status at session boundaries.

## Estimation

Linear `Estimate` is complexity, not effort hours. Use the org ladder from `/Users/sunny/code/agent-config/context/linear-standards.md`: `1, 2, 4, 8, 16`. The maximum is `16`; anything larger must be split. Effort-hour planning is separate and belongs to sprint planning, not this field.

## Definition of Done

A ticket is Done when the scoped change is merged to `main`, relevant local verification has passed or been explicitly skipped with a reason, CI is green, required tests or screenshots are present, docs and OpenAPI specs are updated when touched, and Linear reflects the merged state.

## Deep References

- Brand and voice: `docs/brand/brand-brief-v1.md`
- Search decision: `docs/architecture/search-index-choice-v2.md`
- Parsed speech schema: `docs/architecture/parsed-speech-schema-epac464.md`
- Navigation architecture: `docs/architecture/navigation-architecture-epac47.md`
- SwiftData migration policy: `docs/architecture/swiftdata-schema-migration.md`
- Backend API: `backend/openapi/openapi.json`
- Use-case catalog: `docs/architecture/use-case-catalog.md`
- Org context guidance: `/Users/sunny/code/agent-config/context/README.md`
- Linear standards: `/Users/sunny/code/agent-config/context/linear-standards.md`
