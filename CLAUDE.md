# epac — Engineering Guide

## Project Overview

epac is an iOS civic-engagement app that displays Canada's House of Commons Hansard debates in a group-chat format. Stack: SwiftUI + SwiftData (iOS 17+), Python backend, static website.

Brand and copy decisions live in `docs/brand/brand-brief-v1.md`. Treat that brief as the source of truth for product positioning, tagline, voice, tone, audience, and anti-positioning.

Search backend decisions live in `docs/architecture/search-index-choice-epac452.md`. Use Postgres `tsvector` for v1 search and treat any Meilisearch work as a later migration after canonical records and ranking needs are proven.

Parsed speech schema decisions live in `docs/architecture/parsed-speech-schema-epac464.md`. Treat backend `speeches.intervention_id` as the canonical source-derived speech identity.

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

| Situation | Decision |
|---|---|
| Root view with meaningful state + actions | Add `@Observable` ViewModel |
| Pure/leaf view that only displays data passed to it | No ViewModel; state stays in parent or is passed down |
| Data access (fetching, network, persistence) | Pass `ModelContext` and `Fetch` **as method parameters**; do not store them on ViewModel |
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
- [ ] **Screenshot taken and committed.** `xcrun simctl io FCFAF817-6694-402D-B116-A86EDAF34237 screenshot /tmp/epac-screenshot.png`, then copy to `docs/build-evidence/<ticket>-running.png` and commit to the branch. Reference via raw GitHub URL — never use placeholder asset URLs (they render as broken images).
- [ ] **Evidence posted.** Add a PR comment and a Jira comment with: `BUILD SUCCEEDED` confirmation, the embedded screenshot, and grep/diff output confirming the specific change.
- [ ] **One logical change.** A PR should be explainable in one sentence of *why*, not a list of what. If you feel compelled to write "and also…" in the title, split the PR.
- [ ] **Size.** Aim for < 400 changed lines. Larger changes need a written justification in the description.
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

The daily App Store release pipeline (`scripts/release/generate_release_notes.py`) collects these lines from all PRs merged since the last release tag and writes `ios/fastlane/metadata/en-US/release_notes.txt` automatically. Omit the line for CI, docs, infra, and refactoring PRs that have no visible user impact.

### App Preview Video Regeneration

Regenerate the 30-second App Store preview video with:

```bash
./scripts/marketing/record-app-preview.sh
```

The script launches the app with `--app-preview-mode`, records `AppPreviewRecordingTests/testAppPreviewSequence`, and writes `docs/marketing/preview/app-preview-final.mp4` as H.264 at 886x1920, 30fps, no audio.

### Post-PR-open review

After `gh pr create`, the Developer spawns a subagent in the **Autonomous Code Reviewer** role (see Roles in `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md`). The Developer waits for the Reviewer to report a merge result (merged, or blocked with reasons) before picking up the next ticket. The Developer does not review, fix, or merge directly.

Spawn prompt template (Claude Code, via the Agent tool):

```
You are the Autonomous Code Reviewer for PR #N (https://github.com/sunnypurewal/epac/pull/N), branch <branch>.
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
| PR opened | Comment with PR URL (`https://github.com/sunnypurewal/epac/pull/N`) |
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
