# epac — Engineering Guide

## Project Overview

epac is an iOS civic-engagement app that displays Canada's House of Commons Hansard debates in a group-chat format. Stack: SwiftUI + SwiftData (iOS 17+), Python backend, static website.

Brand and copy decisions live in `docs/brand/brand-brief-v1.md`. Treat that brief as the source of truth for product positioning, tagline, voice, tone, audience, and anti-positioning.

Search backend decisions live in `docs/architecture/search-index-choice-epac452.md`. Use Postgres `tsvector` for v1 search and treat any Meilisearch work as a later migration after canonical records and ranking needs are proven.

Parsed speech schema decisions live in `docs/architecture/parsed-speech-schema-epac464.md`. Treat backend `speeches.intervention_id` as the canonical source-derived speech identity.

Backend API documentation lives in `backend/openapi/openapi.json` and is served by the `backend/openapi` Lambda. Adding or changing a backend endpoint requires updating the OpenAPI spec in the same PR.

### SwiftLint baseline (EPAC-334)

The iOS sources (`ios/**/*.swift`) are linted by SwiftLint under `--strict` (warnings fail the build). The workflow lives at `.github/workflows/swiftlint.yml` and runs on Linux via the `ghcr.io/realm/swiftlint:latest` container — keeps CI cost flat.

Configuration is `.swiftlint.yml` at the repo root. The intent: catch the issues that are real bug-bait (`force_cast`, `force_try`, `empty_count`, `redundant_nil_coalescing`, `explicit_init`) and the auto-fixable formatting issues (`closure_end_indentation`, `sorted_imports`). Rules that mostly produce false positives in a SwiftUI codebase — `convenience_type`, `large_tuple`, `cyclomatic_complexity`, `function_body_length`, `multiple_closures_with_trailing_closure`, `vertical_parameter_alignment`, `identifier_name`, `line_length`, `type_name`, `file_length`, `type_body_length`, `for_where`, `static_over_final_class`, `void_function_in_ternary`, `trailing_newline` — are disabled with a one-line comment in `.swiftlint.yml` explaining why.

Local install + run:

```bash
brew install swiftlint
swiftlint --fix     # auto-fixes formatting (commas, sorted imports, etc.)
swiftlint --strict  # same as CI; expect zero output
```

When you genuinely need to break a rule, use a per-line `// swiftlint:disable:next <rule>` *with a one-line reason* (or a `disable / enable` block for consecutive lines). Examples in `Fetch.swift` and `CommitteeDownloader.swift`. Don't relax the project default to dodge a single site.

The baseline PR (EPAC-334) ran `swiftlint --fix` on the entire `ios/` tree, so most of those 100+ files got mechanical reformatting (comma spacing, colon spacing, sorted imports). Future feature PRs should land clean against this baseline; if a rebase introduces lint regressions, run `swiftlint --fix` first.

### iOS coverage thresholds (EPAC-352, EPAC-625)

The iOS coverage workflow lives at `.github/workflows/ios-coverage.yml`. It runs the `epacTests` unit test target with `xcodebuild test -enableCodeCoverage YES`, excluding `SnapshotTests`, parses the `xccov` JSON report with `scripts/ci/ios_coverage_report.py`, writes a GitHub Actions step summary, and posts or updates one PR comment with changed-module coverage deltas. UI and snapshot tests stay outside this coverage gate because they are slower and less reliable as a module line-coverage signal.

Module thresholds (enforced in CI; specified in EPAC-625):

| Module | Minimum coverage | Scope |
|---|---:|---|
| ViewModels | 60% | `*ViewModel.swift` and `ViewModels/` |
| Services | 50% | `ios/epac/Util/*Service.swift` and `*Manager.swift` |
| Models | 40% | `ios/epac/Model/` |
| Views | 0% | `ios/epac/Views/` (SwiftUI views are not unit-testable; covered by XCUITest) |

Thresholds are enforced only for app modules changed by the PR, so new and modified logic cannot move forward without tests while the historical baseline is raised incrementally. New ViewModel code must include unit tests in the same PR unless the PR description explains why the behavior is only testable through UI or integration coverage.

### Backend Python logging (EPAC-176)

Python ingest scripts under `backend/` emit **structured JSON logs to stderr** — one JSON object per record — never `print()`. Use the `logging` module with the JSON formatter pattern in `backend/cabinet/cabinet_ingest.py` (stdlib only, no third-party dep).

Reserved fields on every record: `timestamp` (UTC, ISO-8601 with `Z`), `level`, `pipeline`, `message`. Pipeline-specific context goes through `extra={...}` and is merged at the top level so log aggregators can index on it directly:

```python
logger.info("pipeline started", extra={"dry_run": args.dry_run, "output": args.output})
logger.info("pipeline finished", extra={"records_processed": len(entries), "duration_ms": ms})
logger.error("fetch failed from pm.gc.ca", extra={"error": f"{type(e).__name__}: {e}", "url": URL, "duration_ms": ms})
```

Every pipeline `main()` must log: a `pipeline started` event, a `pipeline finished` event with `records_processed` and `duration_ms`, and at least one `error`-level event for each handled failure mode (with `error`, `url`, `duration_ms`).

Stdout is reserved for the script's actual JSON payload (e.g. `--dry-run`); logs go to stderr so the two streams stay separately redirectable. Log rotation is the runner's job (cron `logrotate`, GitHub Actions step output, AWS CloudWatch retention) — scripts don't open log files themselves.

When a second Python pipeline needs the same setup, factor `_JSONFormatter` and `_configure_logging` into `backend/_logging.py` and import from both. Until then it stays inline to avoid speculating about a packaging refactor.

Backend environments are split for staging and production. Staging base URL: `https://staging-api.epac.riddimsoftware.com`; production base URL: `https://smun5g2szc.execute-api.us-east-1.amazonaws.com/production`. iOS reads `BackendBaseURL` from `Info.plist` via `BACKEND_BASE_URL` in `ios/Config/*.xcconfig`; Debug uses staging and Release uses production unless CI overrides `BACKEND_BASE_URL`. Backend merges to `main` deploy to staging through `.github/workflows/deploy-staging.yml`; production backend deploys are manual through `.github/workflows/deploy-production.yml`.

### Backend API rate limits (EPAC-225)

All Go Lambda handlers that use `observability.WrapAPIGateway` or `observability.WrapAPIGatewayV2` apply shared `/api/v1/` rate limiting before endpoint logic runs. `live-status` also calls the same limiter directly because it accepts both scheduled poll events and API Gateway events in one handler.

Rate limit keys prefer `X-Device-ID` when present, then fall back to source IP / `X-Forwarded-For`. This avoids punishing iOS users behind carrier NAT when the client can provide an anonymous device-scoped token.

Current limits:

| Endpoint scope | Limit |
|---|---:|
| General `/api/v1/` endpoints | 100 requests / minute |
| `/api/v1/live` | 2 requests / minute |
| `/api/v1/members` and `/api/v1/members/*` | 10 requests / minute |
| `/api/v1/calendar/house.ics` | 1 request / 5 minutes |

Limit hits return `HTTP 429 Too Many Requests` with a JSON error body and `Retry-After` header in seconds. The iOS `NetworkService` honors `Retry-After` and retries within its existing four-attempt retry budget.

---

## Architecture

### iOS: MVVM with `@Observable`

We use MVVM. Each decision below was reached after debate; the reasoning is kept here so future changes can argue against it rather than repeat the conversation.

#### Guiding principle (Fowler, *Presentation Model*, 2004)

> "Presentation Model represents the state and behavior of the presentation independently of the GUI controls used."

MVVM earns its keep when:
- presentation logic is complex enough to be worth extracting and testing independently
- the view would otherwise become a mixed bag of state, side effects, and layout

MVVM does **not** earn its keep when:
- the "ViewModel" holds no state and is just a bag of helpers
- the view is purely compositional (Text, Image, simple layout)

#### Rules in this codebase

**ViewModels accept service dependencies via protocol injection; no singletons in ViewModels.** (EPAC-702)

| Situation | Decision |
|---|---|
| Root view with meaningful state + actions | Add `@Observable` ViewModel |
| Pure/leaf view that only displays data passed to it | No ViewModel; state stays in parent or is passed down |
| Data access (fetching, network, persistence) | Pass `ModelContext` and `Fetch` **as method parameters**; do not store them on ViewModel. For network-abstraction in ViewModels define a protocol (e.g. `SittingCalendarFetching`, `ExpendituresFetching`) and pass `any Protocol` so tests can inject mocks. |
| Session-scoped service state (e.g. `MemberResolver` cache) | Define a protocol (`MemberResolving`), inject via `init` with the real implementation as default — prevents stale state between sessions and enables mock injection in tests without touching SwiftData. |
| `@Query` properties | Stay in Views — SwiftData requirement, not a design choice |
| Side-effect services (image loading with fallback chains, download deduplication) | Separate class is acceptable even if small; name it to reflect the concern (e.g. `MemberDownloadCoordinator`, `PhotoLoader`) |

#### What the MVVM refactor (PR #1) got right

- `SpeechViewModel`: complex state (messages, speakers, resume/replay, sharing). Worth it.
- `ExpendituresViewModel` / `ExpenditureDetailViewModel`: filter + sort state, async loads, share logic. Worth it.
- `MembersViewModel`: filter state, computed filtered list. Worth it.
- `ContentViewModel`: navigation state, deep-link parsing. Worth it.
- `SittingCalendarViewModel`: calendar fetch and visible-range logic. Worth it.
- `SpeakerImageViewModel`: URL-fallback image loading chain with model persistence. The async logic is complex enough to justify a class; calling it a "ViewModel" is a slight misnomer, but the separation is correct.

#### Open debate: `SittingViewModel`

`SittingViewModel` holds only `pendingDownloads: Set<String>` and two methods that look up members and trigger background downloads. It is closer to a **download coordinator** than a ViewModel. Consider renaming to `MemberDownloadCoordinator` and removing the `@Observable` annotation — callers don't observe it. Tracked in EPAC backlog.

#### Firm rule: domain model is free of presentation concepts

`ParliamentMember` must not contain properties whose semantics only make sense in a UI context. The removed `isCurrentUser: Bool { party == .liberal }` was an example of this violation — it conflated "which side of the chat does this speaker appear on?" with domain identity. Chat-side logic belongs in `SpeechViewModel`.

---

## Pull Requests

We follow the spirit of continuous integration: keep branches short-lived (aim for < 1 day; never > 1 week), merge frequently, and keep PRs focused.

### PR Author Checklist

Before requesting review, the author must:

- [ ] **Build passes.** Run `xcodebuild -project epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,id=FCFAF817-6694-402D-B116-A86EDAF34237' build` and confirm `** BUILD SUCCEEDED **` before pushing. Fix any failures — even pre-existing ones — before the PR is opened.
- [ ] **App runs.** Install and launch on the simulator: `xcrun simctl install FCFAF817-6694-402D-B116-A86EDAF34237 <DerivedData>/epac.app && xcrun simctl launch FCFAF817-6694-402D-B116-A86EDAF34237 net.dinglebox.cabinetdoor`
- [ ] **Screenshot taken and committed.** `scripts/evidence/run-evidence.sh capture-evidence --ticket EPAC-N`, then commit `docs/build-evidence/EPAC-N-running.png` to the branch. Reference via the raw GitHub URL printed by the command — never use placeholder asset URLs (they render as broken images).
- [ ] **Evidence posted.** Add a PR comment and a Jira comment with: `BUILD SUCCEEDED` confirmation, the embedded screenshot, and grep/diff output confirming the specific change.
- [ ] **One logical change.** A PR should be explainable in one sentence of *why*, not a list of what. If you feel compelled to write "and also…" in the title, split the PR.
- [ ] **Size.** Aim for < 300 changed lines (tighter target for parallel work — see "Multi-developer workflow" below). Anything > 400 lines needs a written justification in the description and should be split if possible. Never mix feature and refactor in the same PR.
- [ ] **Self-review.** Read your own diff before requesting. Remove debug code, dead comments, stray prints.
- [ ] **Tests.** If the change is testable, tests are included or an existing test is updated.
- [ ] **Screenshots.** UI changes include before/after screenshots in the description.
- [ ] **Jira link.** Reference the ticket (`Resolves EPAC-N`) in the description.
- [ ] **Release note.** If the change is user-facing, add a `Release-Note:` line to the PR description (see below). The daily release pipeline collects these automatically.
- [ ] **Description structure** (see below).

### PR Description Template

```
## Why

One paragraph. What problem does this solve? Why now? Link to the debate or ticket that drove it.

## What changed

Bullet list of the key decisions made. Not a rehash of the diff — the diff shows *what*; this explains *why each decision was made this way*.

## Trade-offs not taken

What alternatives were considered and rejected, and why.

## Test plan

How to verify this works. Steps for the reviewer to follow.

## Screenshots (if UI)

| Before | After |
|--------|-------|
| img    | img   |

Resolves EPAC-N

Release-Note: One-line plain-English summary for App Store What's New (omit if not user-facing)
```

### Release-Note convention

Every PR that ships a user-facing change must include one line in the description:

```
Release-Note: Added onboarding flow with topic picker and notification opt-in
Release-Note: Fixed bill sharing link on older iOS versions
```

The daily App Store release pipeline (`scripts/release/generate_release_notes.py`) collects these lines from all PRs merged since the last release tag and writes `ios/fastlane/metadata/en-CA/release_notes.txt` automatically. Omit the line for CI, docs, infra, and refactoring PRs that have no visible user impact.

### App Preview Video Regeneration

Regenerate the 30-second App Store preview video with:

```bash
./scripts/marketing/record-app-preview.sh
```

The script launches the app with `--app-preview-mode`, records `AppPreviewRecordingTests/testAppPreviewSequence`, and writes `docs/marketing/preview/app-preview-final.mp4` as H.264 at 886x1920, 30fps, no audio.

### Backend Base URL

The iOS app's backend base URL is centralized in `ios/epac/Util/BackendConfig.swift` — services in `Util/` should read `BackendConfig.shared.baseURL` rather than hardcoding their own host.

Debug reads staging from `ios/Config/Debug.xcconfig`; Release reads production from `ios/Config/Release.xcconfig`. TestFlight builds use the `Create Release` workflow's `BACKEND_BASE_URL` override to point at staging before App Store release.

To point a local run at another backend, set the `BACKEND_BASE_URL` environment variable on the active Xcode scheme:

> Edit Scheme → Run → Arguments → Environment Variables → add `BACKEND_BASE_URL=https://your-staging-host.example.com/staging`.

`BackendConfig` accepts the override only when it parses as a valid HTTPS URL; anything else falls back to the `Info.plist` build setting, then the production default.

### Post-PR-open review

After `gh pr create`, the Developer spawns a subagent in the **Autonomous Code Reviewer** role (see Roles in `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md`). The Developer waits for the Reviewer to report a merge result (merged, or blocked with reasons) before picking up the next ticket. The Developer does not review, fix, or merge directly.

Spawn prompt template (Claude Code, via the Agent tool):

```
You are the Autonomous Code Reviewer for PR #N (https://github.com/RiddimSoftware/epac/pull/N), branch <branch>.
Repo root: /Users/sunny/code/epac

Follow the Reviewer role defined in ~/.claude/CLAUDE.md. For this PR:

1. `gh pr diff N` — read the full diff
2. Read /Users/sunny/code/epac/CLAUDE.md (architecture rules, PR standards)
3. Read the linked Jira ticket's acceptance criteria
4. Make ONE consolidated pass of fixes directly on the branch (commit + push)
5. Build: cd ios && xcodebuild -project epac.xcodeproj -scheme epac \
   -destination 'platform=iOS Simulator,id=FCFAF817-6694-402D-B116-A86EDAF34237' build 2>&1 | tail -3
6. Run relevant tests
7. Post one PR comment with: build status, what changed and why, what was left alone and why
8. Squash-merge: gh pr merge N --squash --delete-branch
9. Transition the Jira ticket to Done
10. Report back: merged (commit SHA) OR blocked (reasons)
```

**Why this is structured as a subagent rather than a human-attended review:** PR #3 shipped a broken main build because a merge conflict resolution silently dropped `@MainActor` from `MemberDownloadCoordinator`. A second pass would have caught it. Splitting Developer and Reviewer into separate roles — even when the Reviewer runs as a subagent of the same session — gives the review a clean context window and forces the Reviewer to re-read CLAUDE.md and the diff from scratch.

### PR Reviewer Expectations

The Reviewer is spawned synchronously by the Developer at PR-open and is expected to complete the review-fix-merge cycle **immediately**, in the same session. There is no queue, no waiting, no "I'll get to it." The Developer is blocked on the Reviewer's return.

- **Review immediately.** Do not defer. Do not return control until the PR is merged or definitively blocked with reasons.
- Distinguish blocking from non-blocking findings: prefix non-blocking suggestions with `nit:` or `optional:` in the review comment.
- Approve and merge if the approach is sound, even if you would have done it differently; leave a `nit:` for style.
- Never raise "why didn't you use X?" without also explaining why X would be better for *this specific case*.

### What makes a review delightful

The goal is for every review to feel like a conversation between two engineers who respect each other's time and intent. A delightful review:
- opens with a one-sentence assessment of the overall approach
- distinguishes clearly between required changes, suggestions, and observations
- references concrete evidence (a specific line, a linked article, a test result) for every required change
- ends with an explicit approval or a clearly numbered list of what must change before approval

---

## Multi-developer workflow (EPAC-332)

The team is sized for four developers shipping in parallel. The conventions below exist so concurrent work doesn't collide — most of them are silent enforcement (CODEOWNERS, branch protection, ruleset regex), and only the async standup needs a daily human action.

### Code ownership — `.github/CODEOWNERS`

`.github/CODEOWNERS` auto-assigns the right reviewer when a PR touches a given area. Today the team is solo so everything routes to `@sunnypurewal`; the future area assignments are commented in the file and uncommented as developers join:

| Area | Pattern | Future owner |
|---|---|---|
| ViewModels | `ios/epac/Views/**/*ViewModel.swift` | developer-a |
| Services / Managers | `ios/epac/Util/*Service.swift`, `*Manager.swift` | developer-b |
| Backend pipelines | `backend/**` | developer-c |
| Website | `website/**` | developer-d |
| SwiftData migrations | `ios/epac/Model/Migration.swift`, `ios/epac/Model/Model.swift` | shared (always also `@sunnypurewal`) |

When you add a developer to GitHub, replace the `@developer-x` placeholder, uncomment the line, commit. CODEOWNERS is plain text — no rebuild required.

### PR size target

The PR Author Checklist sets the soft target at < 300 lines and the justification threshold at 400. With four developers in flight, large PRs are the single biggest source of review-queue stalls and post-merge regressions — measure twice, cut once, split early. A PR that touches a feature *and* refactors surrounding code is two PRs; ship the refactor first, then the feature on top.

### Shared model change protocol

Any change to a SwiftData `@Model` (`ParliamentMember`, `Sitting`, `RecordedVote`, `Bill`, `Petition`, …) requires:

1. A new `SchemaVN` and a migration stage in `EpacMigrationPlan` per **ADR-002** (see "SwiftData Schema Migration" below — this is non-negotiable, not just a recommendation).
2. The PR description calls it out under **What changed** with the migration kind (lightweight vs custom) and the rationale.
3. Comment the model PR in the daily async standup thread the same morning so the rest of the team can avoid touching the same models that day.
4. Backend rebuilds the local Postgres + tsvector index (EPAC-452) the same day if the schema change has a backend mirror.

The intent: nobody ever rebases on top of a SwiftData schema change without knowing it landed.

### Daily async standup

The team runs an **async** standup as a single GitHub Discussion thread per sprint (category `Standup`). Every developer posts one comment per working day by **10:00 ET**, in this format:

```
## YYYY-MM-DD — <handle>

- **Today:** EPAC-NNN — <one-line summary> (touching <area / file globs>)
- **Yesterday:** EPAC-NNN merged / EPAC-NNN paused on <reason>
- **Blocked:** none / <ticket + what you need>
```

Why one thread per sprint: searchable history, context survives the week, and "what is X working on?" is one search. Why 10:00 ET: gives the East Coast morning + West Coast wakeup an overlap window before the first PR of the day opens. The Autonomous Developer agent is exempt from posting standups; its activity is already visible on the linked Jira ticket and the open PR list.

The current sprint's Discussion thread is linked from the active sprint's planning ticket in Jira.

---

## Scrum Process

We run **one-week sprints**. This reflects the cadence of Parliament (weekly sitting schedule) and keeps work tightly coupled to what we can ship.

### Roles

For a small team: the developer acts as both Development Team and Product Owner, with Scrum Master responsibilities embedded in the process itself.

### Ceremonies

| Ceremony | When | Duration | Purpose |
|---|---|---|---|
| Sprint Planning | Monday morning | 30 min | Pick backlog items, set the sprint goal |
| Daily check-in | Each morning | 10 min | What's in progress, what's blocked |
| Sprint Review | Friday afternoon | 30 min | Demo what shipped; update Jira |
| Retrospective | Friday afternoon | 20 min | One thing to do differently next sprint |
| Backlog Refinement | Wednesday | 20 min | Estimate and order upcoming items (max 10% of sprint = ~4h/week) |

### Backlog

- The backlog lives in Jira under project **EPAC**.
- Items are ordered by a combination of user value and risk. Risky unknowns are pulled early.
- Each item has: a clear acceptance criterion (definition of done), an effort estimate, and a Jira issue type (Story, Task, or Bug).

### Definition of Done

A ticket is Done when:
1. Code is merged to `main` via an approved PR
2. The app builds without warnings on the current Xcode release
3. Relevant tests pass
4. The Jira ticket is transitioned to Done

### Estimation Convention

We estimate in **hours of focused work** (not story points, not ideal days). After estimating, **divide by 100** before entering the value in the Jira story-points field. This is a deliberate calibration experiment: it keeps estimates small, prevents anchoring, and makes velocity numbers easy to reason about at our scale.

| Real estimate | Jira value |
|---|---|
| 4h | 0.04 |
| 8h | 0.08 |
| 16h | 0.16 |
| 40h | 0.40 |
| 80h | 0.80 |
| 120h | 1.20 |

The Scrum Guide (Schwaber & Sutherland, 2020) is clear: **velocity is a planning tool, not a performance metric.** Do not use it to compare sprints or to pressure estimates.

### Jira Ticket Lifecycle

Every ticket must be kept current. Three moments require action:

| Event | Jira action |
|---|---|
| Picking up a ticket | Transition → **In Progress**; comment with branch name |
| PR opened | Comment with PR URL (`https://github.com/RiddimSoftware/epac/pull/N`) |
| PR merged | Transition → **Done** |

Never open a PR without the ticket already In Progress. Never merge without transitioning to Done.

Transition IDs (EPAC project): To Do = `11`, In Progress = `21`, Done = `31`.

### Backlog Artifacts

Every ticket that ships produces at least one artifact visible in the GitHub monorepo:
- A merged PR (required for all code changes)
- A test file or updated test (required for logic changes)
- A screenshot in the PR description (required for UI changes)

The PR number is linked in the Jira ticket as a comment with the full GitHub URL.

---

## Marketing Automation

### App Preview Video

The App Store App Preview video is produced automatically using an XCUITest. Do not record manually.

**To regenerate the App Preview video** after a significant UI change:

```bash
./scripts/marketing/record-app-preview.sh
```

This script:

1. Builds epac for the iPhone simulator
2. Starts `simctl recordVideo`
3. Runs `AppPreviewRecordingTests/testAppPreviewSequence`
4. Trims and encodes the output to 30 seconds at 886x1920
5. Adds the silent AAC audio track App Store Connect expects
6. Writes `docs/marketing/preview/app-preview-final.mp4`

**When to regenerate:** After any change to `HomeFeedView`, `SpeechView`, `VoteDetailView`, lobbying views, or the contact sheet. The test catches navigation regressions; a failing test means the UI changed in a way that breaks the video sequence.

**Adding a new scene to the video:** Edit `AppPreviewRecordingTests.swift`, add a new scene step, call it from `testAppPreviewSequence()`, and adjust the total duration. Add any new accessibility identifiers needed.

**Upload:** After the script produces the file, upload manually to App Store Connect -> My Apps -> epac -> App Preview (6.9-inch slot). Apple validates the file on upload; check for H.264 format and 886x1920 resolution.

---

## References

- Fowler, M. *Presentation Model*. martinfowler.com, 2004.
- Fowler, M. *Continuous Integration Certification*. martinfowler.com.
- Beck, K. *Tidy First?* O'Reilly, 2023.
- Beck, K. *Extreme Programming Explained*. Addison-Wesley, 1999.
- Schwaber, K. & Sutherland, J. *The Scrum Guide*. scrumguides.org, 2020.
- Apple. *Managing model data in your app*. developer.apple.com/documentation/SwiftUI.
- Apple. *Observation framework*. developer.apple.com, 2023.

---

## Navigation Architecture (ADR-001)

**Date:** 2026-04-27
**Status:** Accepted
**Ticket:** EPAC-47

### Context

The iOS app grew from 3 features to 20+. The original Debates / Members / Expenditures tab structure no longer accommodates Bills, Petitions, Topics, e-Petitions, Following, Riding Stats, Consultations, and the planned Home feed. iOS tab bars support 5 items before requiring a "More" overflow, which buries content and harms discoverability.

### Decision

Adopt a 5-tab structure that groups features thematically and positions the personalized Home feed as the primary entry point:

| Tab | Icon | Homes |
|-----|------|-------|
| **Home** | `person.house.fill` | MyMPView: Your MP activity, followed bills, followed topics, petitions, consultations |
| **Parliament** | `building.columns.fill` | Sitting calendar, Hansard debates, Order Paper |
| **Members** | `person.3.sequence.fill` | MP list, profiles, voting records, comparison |
| **Accountability** | `scalemass.fill` | Bills tracker, Expenditures, e-Petitions, Topics |
| **Search** | `magnifyingglass` | Cross-entity full-text search |

### Rationale

- **Home first**: The personalized feed is the highest-engagement surface. Users who have set their MP, followed bills, or followed topics will see relevant content immediately. First-launch users see a clear prompt to set up.
- **Parliament vs. Members**: Sittings are temporal (what happened today); Members are entities (who are these people). Keeping them separate reflects how users approach them.
- **Accountability hub**: Bills, Expenditures, Petitions, and Topics are all *accountability* tools — how Parliament spends, passes, and responds to citizens. Grouping them under one tab makes the civic function legible.
- **Search as a tab**: Search is a power-user tool that spans all entities. Keeping it visible ensures discoverability for advanced users without cluttering primary tabs.

### Rejected alternatives

- **6 tabs**: iOS renders a "More" overflow at 6+, which buries the last tab and breaks muscle memory. Rejected.
- **Sidebar-only on iPhone**: NavigationSplitView on iPhone has inconsistent swipe behaviour and doesn't feel native. Rejected for phone; retained for iPad (already implemented).
- **No Home tab**: Keeping Debates as the primary tab requires every new feature to compete for a tab slot. Rejected — the personalized feed is the right first screen.

### Constraints

- All 5 existing tabs must continue to function during and after the transition.
- iPad uses NavigationSplitView (`AppTab.allCases` sidebar); the tab order maps directly to sidebar order — no separate iPad logic needed.
- New features must state their navigation home in the PR description before merging.

---

## SwiftData Schema Migration (ADR-002)

**Date:** 2026-04-27
**Status:** Accepted
**Ticket:** EPAC-128

### Convention: every schema change requires a new `SchemaVN`

**Rule:** Any change to a SwiftData `@Model` — adding a property, removing one, renaming one, changing a type, or adding a new model class — requires a new versioned schema enum and a new migration stage in `EpacMigrationPlan`.

**Never** change an existing `SchemaVN` enum after it has shipped in production. Existing versions are immutable; they define what real users' databases look like on disk.

### How to add a new schema version

1. Copy the current latest `SchemaVN` enum in `Model.swift` to a new `SchemaV(N+1)` enum.
2. Make your changes inside `SchemaV(N+1)`.
3. Update the `typealias` block at the top of `Model.swift` to point to `SchemaV(N+1)`.
4. Add a migration stage to `EpacMigrationPlan` in `Migration.swift`:
   - Adding optional properties or new model types → `MigrationStage.lightweight`
   - Adding non-optional properties, renaming, or transforming data → `MigrationStage.custom` with a `didMigrate` closure
5. Add `SchemaV(N+1).self` to `EpacMigrationPlan.schemas`.

### When to use lightweight vs custom migration

| Change | Stage |
|--------|-------|
| New optional property | Lightweight |
| New `@Model` class | Lightweight |
| New non-optional property (needs default) | Custom — set value in `didMigrate` |
| Rename a property | Custom — read old, write new, nil out old |
| Remove a property | Lightweight (SwiftData ignores unknown columns) |
| Change a property type | Custom |

### Migration plan location

`ios/epac/Model/Migration.swift` contains `EpacMigrationPlan`. The `ModelContainer` in `epacApp.swift` initializes with this plan. The plan accumulates all migration stages in chronological order; do not remove old stages.

### Why not destructive migration

The previous fallback — delete the SQLite files on schema incompatibility — silently destroyed all locally cached Hansard data, votes, and expenditures on every schema update. For a civic app users rely on during active political moments, losing the local cache is a bad experience. Proper migrations preserve data across updates.

---

---

## Autonomous PR Loop

epac uses the RiddimSoftware autonomous PR loop for routine changes. The loop handles the full developer → review → merge cycle without human intervention.

**Runbooks (in `RiddimSoftware/riddim-release`):**
- [Onboarding guide](https://github.com/RiddimSoftware/riddim-release/blob/main/docs/agent-loop/onboarding.md) — how to enroll a new repo, branch protection settings, smoke test procedure
- [Failure runbook](https://github.com/RiddimSoftware/riddim-release/blob/main/docs/agent-loop/failure-runbook.md) — how to read labels, pause a runaway loop, find Action logs, and perform manual overrides

**Quick reference:**
- Add `agent:build` to an issue to trigger the developer bot.
- Add `agent:pause` to a PR to halt the loop immediately.
- `agent:needs-human` means the attempt cap was hit — review the PR manually.
- `startup_failure` on the reviewer job for a human-opened PR is **expected** — the reviewer only runs on developer-bot PRs.
- If `agent:build` never fires: confirm Issues are enabled in Settings → Features.
