# epac — Engineering Guide

## Project Overview

epac is an iOS civic-engagement app that displays Canada's House of Commons Hansard debates in a group-chat format. Stack: SwiftUI + SwiftData (iOS 17+), Python backend, static website.

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
```

### PR Reviewer Expectations

- Respond within one working day.
- Distinguish blocking from non-blocking comments: prefix suggestions with `nit:` or `optional:` if they are not required for merge.
- Approve if the approach is sound, even if you would have done it differently; leave a `nit:` comment for style.
- Never ask "why didn't you use X?" without also explaining why X would be better for *this specific case*.

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
