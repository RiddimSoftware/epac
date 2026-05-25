# Cyclomatic-complexity pilot — coverage map

Worked example for the regression-evidence methodology, run against the [Enforce cyclomatic complexity ≤ 5 across iOS codebase](https://linear.app/riddimsoftware/project/enforce-cyclomatic-complexity-5-across-ios-codebase-7cab4105228e) Linear project. This document is the **input** the future `evidence-pr-merged.yml` workflow and `evidence-project-rollup.yml` workflow will derive automatically from any Linear project — captured here manually as the first run so the playbook can be extracted from it.

## Project facts

- **Linear project:** `Enforce cyclomatic complexity ≤ 5 across iOS codebase` (`09b177b0-1644-4668-8770-138e080f5d33`)
- **Handoff ticket:** [EPAC-1997](https://linear.app/riddimsoftware/issue/EPAC-1997)
- **Pilot scope (Fork 3):** Parliament-tab user stories only. Other tabs are out of pilot scope; documented per-PR below.
- **Pre-project main SHA:** `9ba487ca2fdb2ecfa4fe722d0c353944284bc9ff` (parent of PR #542's merge commit, i.e. main immediately before the first project PR squashed in)
- **Post-project main SHA:** `79e3b0bc2904dcc69e53975142deb4283f5f8c6d` (PR #558's merge commit, i.e. main after the integration PR locked the lint threshold)

## PR roster — chronological merge order

| # | PR | Linear | Title | After-SHA | Files touched | Parliament-tab in scope? |
|---|---|---|---|---|---|---|
| 1 | [#542](https://github.com/RiddimSoftware/epac/pull/542) | [EPAC-1985](https://linear.app/riddimsoftware/issue/EPAC-1985) | reduce ContentView deep-link complexity | `b4ca95dd` | `ios/epac/Views/ContentView.swift` | **YES** — deep-link routes include sitting / event / speech URLs landing on Parliament tab |
| 2 | [#543](https://github.com/RiddimSoftware/epac/pull/543) | [EPAC-1987](https://linear.app/riddimsoftware/issue/EPAC-1987) | reduce XMLBro parser complexity | `20f70fe4` | `ios/epac/Util/XMLBro.swift` | **YES** — Hansard XML parser, direct Parliament-tab read path |
| 3 | [#546](https://github.com/RiddimSoftware/epac/pull/546) | [EPAC-1984](https://linear.app/riddimsoftware/issue/EPAC-1984) | reduce Fetch.swift cyclomatic complexity | `b141f1c4` | `ios/epac/Model/Fetch.swift` | **YES** — `downloadCalendar` + `downloadHansard` are the Parliament-tab data adapters |
| 4 | [#547](https://github.com/RiddimSoftware/epac/pull/547) | [EPAC-1988](https://linear.app/riddimsoftware/issue/EPAC-1988) | reduce LobbyistService parser complexity | `f7ca8867` | `ios/epac/Util/LobbyistService.swift`, `LobbyistServiceTests.swift` | NO — lobbyist data not surfaced on Parliament tab |
| 5 | [#548](https://github.com/RiddimSoftware/epac/pull/548) | [EPAC-1994](https://linear.app/riddimsoftware/issue/EPAC-1994) | extract Hansard speaker parser | `0fdeed38` | `ios/epac/Util/HansardSpeakerParser.swift` (new), `XMLBro.swift`, `BugTests.swift` | **YES** — Hansard speaker-line parsing, feeds `ParliamentMember` resolution in the speech reader |
| 6 | [#549](https://github.com/RiddimSoftware/epac/pull/549) | [EPAC-1995](https://linear.app/riddimsoftware/issue/EPAC-1995) | reduce city council model parser complexity | `8b52bf37` | `TorontoCityCouncil.swift`, `VancouverCityCouncil.swift` | NO — city council data, no Parliament-tab surface |
| 7 | [#550](https://github.com/RiddimSoftware/epac/pull/550) | [EPAC-1993](https://linear.app/riddimsoftware/issue/EPAC-1993) | reduce service complexity | `d56fd866` | CommitteeSummary, Gazette, PBO, RidingLookup, Senators services | NO — none of these surface on Parliament tab |
| 8 | [#552](https://github.com/RiddimSoftware/epac/pull/552) | [EPAC-1989](https://linear.app/riddimsoftware/issue/EPAC-1989) | reduce expenditure CSV parser complexity | `22c1ae5d` | `ios/epac/Model/Expenditures+CSV.swift` | NO — Accountability tab |
| 9 | [#553](https://github.com/RiddimSoftware/epac/pull/553) | [EPAC-1990](https://linear.app/riddimsoftware/issue/EPAC-1990) | reduce CalendarExportService complexity | `8291f609` | `ios/epac/Util/CalendarExportService.swift` | **PARTIAL** — EventKit export action lives on the SittingCalendarView toolbar (Parliament-tab UI). Regression risk is in the export flow, not in the rendering. |
| 10 | [#554](https://github.com/RiddimSoftware/epac/pull/554) | [EPAC-1991](https://linear.app/riddimsoftware/issue/EPAC-1991) | reduce SearchViewModel.rebuildResults complexity | `f5e59907` | `ios/epac/Views/Search/SearchViewModel.swift` | NO — Search tab |
| 11 | [#555](https://github.com/RiddimSoftware/epac/pull/555) | [EPAC-1992](https://linear.app/riddimsoftware/issue/EPAC-1992) | reduce MyMP view complexity | `8099fa3c` | `ios/epac/Views/MyMP/MyMPView.swift` | NO — Home tab MyMP |
| 12 | [#557](https://github.com/RiddimSoftware/epac/pull/557) | [EPAC-1986](https://linear.app/riddimsoftware/issue/EPAC-1986) | reduce BillsService complexity | `3e6afb06` | `ios/epac/Util/BillsService.swift` | NO — Accountability tab (Bills) |
| 13 | [#558](https://github.com/RiddimSoftware/epac/pull/558) | [EPAC-1996](https://linear.app/riddimsoftware/issue/EPAC-1996) | lock cyclomatic_complexity error threshold to 5 | `79e3b0bc` | `.swiftlint.yml` | NO — config only, no runtime behavior change |

**In-scope for the pilot plan:** PRs #542, #543, #546, #548, #553 — **5 of 13 PRs**.

## Why these specific PRs are in scope

Mapping each in-scope PR's touched code to the Parliament-tab user stories (per [`docs/architecture/use-case-catalog.md`](../architecture/use-case-catalog.md)):

### PR #542 — `ContentView.swift` deep-link handlers (EPAC-1985)

- **Use cases touched:** entry-point routing to `BrowseTodayInParliament`, `GetSittingSpeeches`, `ReadHansardSpeech`
- **Specific routes the refactor must preserve (from [`docs/architecture/deep-link-routes.md`](../architecture/deep-link-routes.md)):**
  - `cs-sitting` (`cabinetdoor://sitting/{date}`)
  - `cs-event` (`cabinetdoor://event/{date}`, alias)
  - `ul-sitting` (`https://epac.riddimsoftware.com/sitting/{date}`)
  - `ul-speech` (`https://epac.riddimsoftware.com/speech/{id}`)
  - `ul-app-legacy` (`/app?date=…&subjectID=…`)
  - `ul-app-encoded-path` (`/app?path=…`)

### PR #543 — `XMLBro.swift` Hansard parser (EPAC-1987)

- **Use cases touched:** `IngestHansard` (parsing) → `GetSittingSpeeches` → `ReadHansardSpeech`
- **Observable surface:** every Hansard speech the user reads in the chat-format view. A regression here would manifest as missing/garbled speakers, wrong subject grouping, or empty speech bodies.

### PR #546 — `Fetch.swift` data adapter (EPAC-1984)

- **Use cases touched:** `BrowseTodayInParliament` (via `downloadCalendar`), `ReadHansardSpeech` (via `downloadHansard`)
- **Observable surface:** the sitting calendar populating from `ourcommons.ca`, the per-sitting Hansard download succeeding, on-disk SwiftData state matching the parsed XML.

### PR #548 — extract `HansardSpeakerParser` (EPAC-1994)

- **Use cases touched:** `ReadHansardSpeech` (speaker resolution for each message bubble)
- **Observable surface:** speaker labels and party affiliations on each chat bubble in the speech reader. A regression here would surface as wrong/missing names, wrong party tag, or speeches attributed to the wrong member.

### PR #553 — `CalendarExportService.swift` EventKit export (EPAC-1990, partial)

- **Use cases touched:** `BrowseTodayInParliament` (toolbar action), `GetHouseCalendar` (UI invocation, not the ICS feed itself)
- **Observable surface:** tapping the calendar-export toolbar item on `SittingCalendarView` triggers the EventKit permission flow and writes events.
- **Why partial:** the rendering of the Parliament tab is unaffected; only the export side-effect is. The plan covers presenting the export toolbar; the actual EventKit interaction is out of pilot scope (requires runtime permission, can't be captured deterministically via simctl).

## Fixture-seed requirements

For the plan's deep-links to land on real (non-empty) surfaces, the in-memory SwiftData store needs the following seeded under `EPAC_EVIDENCE_MODE=1`:

| Entity | Count | Minimum fields needed for the plan |
|---|---|---|
| `Sitting` | ≥ 1 | `date`, `parliament`, `session`, `url` |
| `Hansard` | ≥ 1 | tied to a seeded `Sitting` |
| `SubjectOfBusiness` | ≥ 2 | tied to a seeded `Hansard` (so the plan can hit `subjectID` in the legacy `/app` URL) |
| `SpeechMessage` | ≥ 5 across at least one subject | speaker name, party, text content; tied to a `SubjectOfBusiness` |
| `ParliamentMember` | ≥ 3 | so speech bubbles show speakers; chosen IDs must be the ones the plan deep-links to (`/member/{id}`) — but member routes are out of pilot scope, so this is only for speech-attribution rendering |

**Concrete fixture set** for `regression-parliament-calendar.json` to reference (real Hansard data, downloaded from `ourcommons.ca`, bundled in the app under `ios/epac/Resources/EvidenceFixtures/`):

| Fixture name | Sitting date | Source URL | File size |
|---|---|---|---|
| `45-1-HAN050-E` (**default**) | Tuesday, November 4, 2025 | `https://www.ourcommons.ca/Content/House/451/Debates/050/HAN050-E.XML` | 543 KB |
| `45-1-HAN070-E` | Tuesday, December 9, 2025 | `https://www.ourcommons.ca/Content/House/451/Debates/070/HAN070-E.XML` | 729 KB |
| `45-1-HAN100-E` | Thursday, March 26, 2026 | `https://www.ourcommons.ca/Content/House/451/Debates/100/HAN100-E.XML` | 556 KB |

All three fixtures are sittings where both **Prime Minister Mark Carney** (`DbId 317577`) and **Leader of the Opposition Pierre Poilievre** (`DbId 322130`) spoke. That gives the QA reviewer (human or LLM) two recognizable speakers to verify rendering against — the speech-view screenshot of a Question Period exchange between the two is unmistakable, which makes regressions in speaker attribution, name parsing, or affiliation rendering instantly visible.

Three fixtures provide redundancy: if one XML's content trips an `XMLBro` edge case, the others can be selected via the `EPAC_EVIDENCE_FIXTURE` env var (set in the plan's `launch.environment` block). Within a single capture-pr run, the same value is passed to both phase launches so the seeded state matches across before/after. Between runs, the value can rotate.

`EvidenceFixtureSeed` (`ios/epac/Util/EvidenceFixtureSeed.swift`) reads the env var, loads the named bundle XML, and calls `Fetch.ingestHansard(xml:)` — the same parse-and-persist code path `Fetch.downloadHansard` uses after its URLSession download. This means the seed itself exercises `XMLBro.parseXML`, `HansardSpeakerParser`, and the `Hansard` SwiftData mapping: a regression in any of those manifests as a seed failure (empty Parliament tab) before the evidence plan's deep links fire.

For the cyclomatic pilot, `regression-parliament-calendar.json` pins `EPAC_EVIDENCE_FIXTURE = 45-1-HAN050-E` (Nov 4, 2025), and its URL payloads use:
- Sitting date: `2025-11-04` (used in `cs-sitting`, `cs-event`, `ul-sitting`, `ul-app-legacy`, `ul-app-encoded-sitting`)
- Subject ID: `1` (used in `ul-app-legacy` query parameter — the first `OrderOfBusiness` in any Hansard XML)
- Speech intervention ID: `13220089` (the Hansard root element's `id` attribute in `45-1-HAN050-E.XML`)

## Plan structure (for `regression-parliament-calendar.json`)

Single `simctl` plan, one boot per revision. Scope: deep-link entry into Parliament-tab surfaces, against seeded fixtures.

```
01: launch (EPAC_EVIDENCE_MODE=1, fixtures seeded)
02: wait 2.0s → screenshot 00-launch-baseline.png

# Sitting calendar entry
03: openURL cabinetdoor://sitting/2024-09-16   → screenshot cs-sitting.png
04: openURL cabinetdoor://event/2024-09-16     → screenshot cs-event.png   (alias of cs-sitting)
05: openURL https://epac.riddimsoftware.com/sitting/2024-09-16 → ul-sitting.png

# Speech entry
06: openURL https://epac.riddimsoftware.com/speech/12345 → ul-speech.png

# Legacy share format (Parliament-tab destination via legacy /app?date=)
07: openURL https://epac.riddimsoftware.com/app?date=2024-09-16&subjectID=1 → ul-app-legacy.png

# Encoded-path recursive routing (resolves to sitting destination)
08: openURL https://epac.riddimsoftware.com/app?path=%2Fsitting%2F2024-09-16 → ul-app-encoded-sitting.png

# Negative cases (Parliament-tab read path edge cases)
09: openURL cabinetdoor://nothing/123                 → screenshot cs-unrecognized.png  (no-op)
10: openURL https://epac.riddimsoftware.com/notarealroute → screenshot ul-unknown-fallback.png (Home)
```

**8 captures + 1 baseline = 9 screenshots per revision**, one simulator boot per revision, ~2 minutes per warm build + ~30 seconds capture = under 5 minutes per revision on a hot SPM cache.

### Scope statement (lands in the plan's `_doc` field and the report's preamble)

> This plan exercises Parliament-tab entry surfaces reachable via the deep-link router: sitting overview, Hansard speech rendering, legacy share format, encoded-path routing, and the home-fallback safety net. It covers the read path through `Fetch.downloadHansard` / `Fetch.downloadCalendar`, `XMLBro.parseXML`, `HansardSpeakerParser`, and `ContentView.handleCustomScheme` / `handleUniversalLink`.
>
> Out of scope: in-app calendar UI navigation (tapping a date, scrolling months); SpeechView replay/scroll interactions; speaker-photo loading; EventKit export interactions (requires runtime permission); Members / Accountability / Search / Home tabs.

## Project-scope vs. per-PR runs

For the cyclomatic pilot specifically:

- **Project-scope run (handoff artifact for EPAC-1997):** `regression-parliament-calendar.json` against `before=9ba487ca…` (pre-project) vs. `after=79e3b0bc…` (post-project). One run, attached to EPAC-1997 as the gating evidence.
- **Per-PR runs (forensic, if any project-scope diff fails):** `regression-parliament-calendar.json` against each in-scope PR's before/after SHAs (#542, #543, #546, #548, #553) — five runs, used only if the project-scope diff is non-trivial and we need to localize the regression to a specific PR.

This pilot doesn't have the `evidence-pr-merged.yml` workflow yet — the per-PR runs would have happened automatically at merge time once that workflow is in place. For this pilot, the project-scope run is the single artifact.

## What this exercise reveals about the playbook

Three patterns that should be encoded once the methodology is codified:

1. **PR → surface mapping requires per-issue judgment** but is mostly mechanical. Inputs: list of touched files, area patterns. Output: in-scope / partial / out-of-scope tag per PR. A path-glob registry (`.evidence/routing.yml`) can automate ~90% of this; the "partial" cases (PR #553 here) need a human judgment call once per file pattern.

2. **Fixture requirements are derived from the plan's URL payloads**, not from the PRs themselves. Once an area plan exists, its fixture contract is fixed. New PRs in the same area inherit the fixture contract for free.

3. **Project-scope is a no-op vs. per-PR if no in-scope PR exists.** If a Linear project doesn't touch any of the registered area plans, the project's regression run is just the boundary build smoke test — fast and cheap. The cost of regression coverage scales with surface impact, not with project size.

## What to codify into Linear next

After running this pilot end-to-end and validating the methodology, the items to file (per the design discussion):

1. Seed deterministic fixtures into in-memory SwiftData under `EPAC_EVIDENCE_MODE=1` — contract = the fixture set above
2. Author `regression-parliament-calendar.json` — content = the plan above
3. Add `.evidence/routing.yml` and `evidence-pr-merged.yml` — encodes the PR → area mapping above
4. Implement the QA-LLM verdict step + Linear issue creation for inconclusive / empty-state findings
5. Add `evidence-project-rollup.yml` — enumerates a Linear project's PRs (this exercise, automated)
6. Write `docs/regression/project-handoff-playbook.md` — generalize from this document
