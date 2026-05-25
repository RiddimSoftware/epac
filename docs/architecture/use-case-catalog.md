# epac Use-Case Catalog

> **Catalog update rule:** Any PR that creates, renames, removes, or materially changes a cataloged use case must update the relevant entry in this file in the same PR. "Material change" means a new input, output, port, or actor — not internal refactoring of the adapter layer.

This catalog describes application policy (what epac does) without importing or requiring SwiftUI, SwiftData, UIKit, Lambda event types, APNs, `pgx`, or URLSession types. Delivery adapters are listed under *Primary adapters* as named artifacts, not as architectural definitions.

For the Clean Architecture shape this catalog assumes, see [`docs/architecture/`](.) and the org guidance at `/Users/sunny/code/skills/arch-team/references/clean-architecture.md`.

---

## Entities / Value Objects

| Name | Description |
|---|---|
| `Hansard` | SwiftData persistence model for a single federal sitting's parsed debate record; adapter detail, not application policy. |
| `HansardTranscript` | Pure Swift transcript entity for a sitting's debate record, carrying jurisdiction, source, language, sitting metadata, and subject records. |
| `Jurisdiction` | Jurisdiction discriminator for federal and provincial Hansard transcript sources. |
| `SubjectOfBusinessRecord` | Pure Swift subject section within a jurisdiction-aware Hansard transcript. |
| `SpeechMessageRecord` | Pure Swift speaker intervention record with source ID, speaker identity, text, timestamp, and word count. |
| `SubjectOfBusiness` | A labelled section within a Hansard (e.g., "Oral Questions"). |
| `SpeechMessage` | One speaker's intervention within a subject, with text, word count, and member reference. |
| `RecordedVote` | A House of Commons division record with date, bill reference, result, and member ballot. |
| `MemberID` | The stable source identifier used to address a ParliamentMember across backend artifacts. |
| `ParliamentMember` | An elected Member of Parliament with riding, party, and contact info. |
| `Sitting` | A House sitting date with Parliament/session metadata and source URL. |
| `Bill` | A Parliament of Canada bill with number, title, stage, sponsor, and LEGISinfo source URL. |
| `ParliamentaryTopic` | A named theme (e.g., "Housing") with associated keyword matchers. |
| `DeviceSubscription` | An APNs token plus the topic/bill/member preferences registered for that device. |
| `LiveParliamentStatus` | A snapshot of whether the House is currently sitting, what business is in progress, and whether a division is active. |
| `OnThisDayItem` | A backend-only historical Parliament moment for the same calendar day in prior years. |
| `EstimateOrg` | A GC InfoBase organization identifier and display name used to group Main Estimates rows. |
| `RidingBoundary` | A simplified federal electoral district boundary with source metadata and GeoJSON geometry. |
| `CalendarEntry` | A House sitting day represented in the public RFC 5545 calendar feed. |
| `AppConfig` | Backend-provided app version and feature-flag settings. |
| `ArtifactKey` | A published object key used by backend artifact publishers, such as `members/v1/all.json`. |
| `Manifest` | The root manifest.json document: schema version, generation timestamp, and sorted artifact entries. |
| `ManifestEntry` | Metadata for one S3 artifact: key, size, SHA-256 hash, ETag, last-modified, and per-artifact schema version. |

## Ports

| Name | Direction | Description |
|---|---|---|
| `HansardRepository` | outbound | Load and store parsed Hansard records. |
| `MemberRepository` | outbound | Resolve member records by ID, name, or riding. |
| `SittingRepository` | outbound | List sitting dates and load speeches for a sitting date. |
| `BillRepository` | outbound | List bills and resolve bill details by number. |
| `MemberContentRepository` | outbound | Load per-member append-only content feeds such as speeches and recorded votes. |
| `TopicPreferenceStore` | outbound | Read and persist a device's followed topics and granularity settings. |
| `DeviceRegistrationClient` | outbound | Persist a device's APNs token and subscription preferences to the backend. |
| `LiveParliamentStatusFetching` | outbound | Fetch the current House sitting status from the backend cache. |
| `NotificationDelivering` | outbound | Send push notifications to subscribed devices via APNs. |
| `SubjectsRepository` | outbound | Read Hansard subject records for artifact generation. |
| `Clock` | outbound | Provide the current timestamp for scheduling and cache-freshness checks. |
| `ArtifactStore` | outbound | Backend publishers and Lambdas list artifact keys, read object data, and write manifest.json back to object storage. |
| `StatisticsSink` | outbound | Backend statistics pipelines write deterministic JSON dataset artifacts without coupling parser logic to stdout, local files, Postgres, or S3 SDK details. |
| `EstimatesReader` | outbound | Fetch published Main Estimates rows by fiscal year, organization, or full artifact export. |
| `RidingBoundaryRepository` | outbound | Read federal riding boundary artifacts by slug. |
| `CalendarArtifactRepository` | outbound | Read the published House sitting calendar ICS artifact. |
| `AppConfigRepository` | outbound | Read backend-provided app configuration artifacts. |

---

## Use Cases

### BrowseTodayInParliament

```
Actor: User (iOS app, foreground)
Goal: View the sitting calendar and today's scheduled subjects of business.
Inputs: Selected date (defaults to today), calendar window (visible month range).
Outputs: List of sittings with subjects, sitting status (scheduled / cancelled / in-progress).
Entities / values: Hansard, SubjectOfBusiness, LiveParliamentStatus.
Ports: HansardRepository, LiveParliamentStatusFetching, Clock.
Primary adapters: SittingCalendarViewModel, SittingCalendarView, Fetch (ourcommons.ca sitting calendar parsing), SwiftDataHansardRepository.
Current implementation:
  ios/epac/Application/BrowseHansardSitting.swift
  ios/epac/Views/Calendar/SittingCalendarViewModel.swift
  ios/epac/Views/Calendar/SittingCalendarView.swift
  ios/epac/Views/Calendar/SittingView.swift
  ios/epac/Views/Calendar/SittingViewModel.swift
  ios/epac/Model/Fetch.swift (downloadCalendar)
```

> **Boundary note:** Calendar-window browse policy now lives in `BrowseHansardSitting` under `ios/epac/Application/`. `SittingCalendarViewModel` consumes that use case through dependency injection and keeps presentation state only.

---

### LoadDailyHansard

```
Actor: User (iOS app, foreground) / Background refresh
Goal: Load one jurisdiction's Hansard transcript for a sitting date and persist it for later read/browse flows.
Inputs: Jurisdiction, sitting date.
Outputs: HansardTranscript.
Entities / values: HansardTranscript, SubjectOfBusinessRecord, SpeechMessageRecord, Jurisdiction.
Ports: HansardRepository.
Primary adapters: SwiftDataHansardRepository, Fetch (downloadHansard), SwiftData (Hansard / SubjectOfBusiness / Message models).
Current implementation:
  ios/epac/Application/LoadDailyHansard.swift
  ios/epac/Domain/Ports/HansardRepository.swift
  ios/epac/Data/Repositories/SwiftDataHansardRepository.swift
```

> **Boundary note:** Fetch-and-store orchestration is an Application use case. SwiftData and network details remain behind `HansardRepository`.

---

### BrowseHansardSitting

```
Actor: User (iOS app, foreground)
Goal: Browse jurisdiction-aware sitting dates and the subjects available for each date in a calendar window.
Inputs: Jurisdiction, start date, end date.
Outputs: Sitting dates and per-date subject summaries.
Entities / values: HansardTranscript, SubjectOfBusinessRecord, Jurisdiction.
Ports: HansardRepository.
Primary adapters: SittingCalendarViewModel, SittingCalendarView, SwiftDataHansardRepository.
Current implementation:
  ios/epac/Application/BrowseHansardSitting.swift
  ios/epac/Views/Calendar/SittingCalendarViewModel.swift
  ios/epac/Data/Repositories/SwiftDataHansardRepository.swift
```

> **Boundary note:** The application policy for window filtering and subject aggregation is no longer in `SittingCalendarViewModel`.

---

### ReadHansardSpeech

```
Actor: User (iOS app, foreground)
Goal: Read a Hansard debate as a group-chat conversation thread.
Inputs: Sitting date, subject-of-business selection.
Outputs: Ordered list of SpeechMessages with speaker names, photos, and text; resume position; replay state.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage, ParliamentMember.
Ports: HansardRepository, MemberRepository, Clock.
Primary adapters: SpeechViewModel, SpeechView, SpeakerImageViewModel, MemberDownloadCoordinator, SwiftDataHansardRepository, Fetch (downloadHansard), SwiftData (Hansard / SubjectOfBusiness / Message models).
Current implementation:
  ios/epac/Application/ReadHansardSpeech.swift
  ios/epac/Views/Chat/SpeechViewModel.swift
  ios/epac/Views/Chat/SpeechView.swift
  ios/epac/Views/Chat/SpeakerImageViewModel.swift
  ios/epac/Views/Calendar/MemberDownloadCoordinator.swift
  ios/epac/Model/Fetch.swift (downloadHansard)
  ios/epac/Model/Model.swift (Hansard, SubjectOfBusiness, Message)
```

> **Boundary note:** Ordered speech loading now lives in `ReadHansardSpeech` under `ios/epac/Application/`. `SpeechViewModel` consumes that use case through dependency injection and keeps presentation state such as replay, sharing, resume position, and resolved speaker display.

---

### SearchHansard

```
Actor: User (iOS app, foreground) or User (iOS app, Spotlight)
Goal: Find Hansard debates, members, bills, or votes matching a text query.
Inputs: Query string, optional entity-type filter.
Outputs: Ranked list of matching results with entity type, title, and navigation hint.
Entities / values: Hansard, SubjectOfBusiness, ParliamentMember.
Ports: HansardRepository, MemberRepository.
Primary adapters (backend): None. Backend search routes and Lambda were retired by EPAC-1921.
Primary adapters (iOS): SearchViewModel, SearchView, NetworkService.
Current implementation:
  ios/epac/Views/Search/SearchViewModel.swift
  ios/epac/Views/Search/SearchView.swift
  ios/epac/Util/NetworkService.swift
```

> **Boundary note:** An explicit `SearchHansard` use case type is introduced by EPAC-1742. Until that PR lands, search policy lives in `SearchViewModel`. The catalog entry is documented here so the boundary target is visible.

---

### FindMyMP

```
Actor: User (iOS app, onboarding or settings)
Goal: Identify the user's Member of Parliament by postal code and save the result for the Home feed.
Inputs: Postal code string.
Outputs: Matched ParliamentMember (or not-found); persisted "my MP" preference.
Entities / values: ParliamentMember.
Ports: MemberRepository.
Primary adapters: PostalCodeViewModel, PostalCodeSetupView, MyMPView, RidingLookupService (calls represent.opennorth.ca), TopicFollowStore (persists myMPMemberId).
Current implementation:
  ios/epac/Views/MyMP/PostalCodeViewModel.swift
  ios/epac/Views/MyMP/PostalCodeSetupView.swift
  ios/epac/Views/MyMP/MyMPView.swift
  ios/epac/Util/RidingLookupService.swift
  ios/epac/Util/TopicFollowStore.swift (myMPMemberId storage)
```

---

### ListMembers

```
Actor: User (iOS app, Members tab) / Backend API caller
Goal: Browse members of Parliament with optional province and party filters.
Inputs: Province filter, party filter.
Outputs: MembersResponse with ParliamentMember records.
Entities / values: ParliamentMember.
Ports: MemberRepository.
Primary adapters: members Lambda (GET /api/v1/members), members-publisher S3 artifact job, S3 members/v1 artifacts, iOS Fetch (ourcommons.ca member XML parsing).
Current implementation:
  backend/members/main.go
  backend/members-publisher/main.go
```

> **Adapter note:** EPAC-1914 moves the backend API path from direct Postgres reads to `members/v1/all.json` in S3. iOS member-list refresh remains on the authoritative Parliament XML source. The publisher remains the only Postgres reader for this use case.

---

### ListSittings

```
Actor: User (iOS app, Calendar / Hansard entry points) / Backend API caller
Goal: Browse House sitting dates and their source metadata.
Inputs: Page, per-page, optional from_date and to_date filters.
Outputs: SittingsResponse with Sitting records.
Entities / values: Sitting.
Ports: SittingRepository.
Primary adapters: sittings Lambda (GET /api/v1/sittings), sittings-publisher S3 artifact job, S3 sittings/v1 artifacts, iOS Fetch (ourcommons.ca sitting calendar parsing).
Current implementation:
  backend/sittings/main.go
  backend/sittings-publisher/main.go
```

> **Adapter note:** EPAC-1914 moves the backend API path from direct Postgres reads to `sittings/v1/all.json` in S3. iOS sitting-calendar refresh remains on the authoritative Parliament calendar page. The publisher remains the only Postgres reader for the sitting index.

---

### GetSittingSpeeches

```
Actor: User (iOS app, Hansard speech reader) / Backend API caller
Goal: Read paginated Hansard interventions for one sitting date.
Inputs: Sitting date, page, per-page.
Outputs: SpeechesResponse with source-derived intervention IDs and speech content.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage, Sitting.
Ports: HansardRepository, SittingRepository.
Primary adapters: sittings Lambda (GET /api/v1/sittings/{date}/speeches), sittings-publisher S3 by-date artifacts, iOS Fetch (ourcommons.ca Hansard XML parsing).
Current implementation:
  backend/sittings/main.go
  backend/sittings-publisher/main.go
```

> **Adapter note:** EPAC-1914 returns HTTP 404 when the date artifact is missing and does not fall back to Postgres. iOS Hansard loading remains on the authoritative Parliament XML export and persists parsed SwiftData records locally.

---

### ListBills

```
Actor: User (iOS app, Bills tab) / Backend API caller
Goal: Browse current-session bills with optional status and parliament filters.
Inputs: Status filter, Parliament number.
Outputs: BillsResponse with Bill records.
Entities / values: Bill.
Ports: BillRepository.
Primary adapters: bills Lambda (GET /api/v1/bills), bills-publisher artifact job, S3 bills/v1 artifacts, iOS BillsService (LEGISinfo JSON).
Current implementation:
  backend/bills/main.go
  backend/bills-publisher/main.go
```

> **Adapter note:** EPAC-1914 moves the backend API path to `bills/v1/all.json` in S3. iOS bill-list reads use the authoritative LEGISinfo JSON feed directly. The current repo has no bills table, so the publisher uses the same source until a canonical backend bills table exists.

---

### GetOnThisDay

```
Actor: Backend API caller
Goal: Serve prior-year Parliament moments for the same calendar day while backend teardown work is pending.
Inputs: Reference date, item limit.
Outputs: OnThisDayResponse with ranked OnThisDayItem records.
Entities / values: OnThisDayItem, SpeechMessage.
Ports: HansardRepository.
Primary adapters: on-this-day Lambda (GET /api/v1/on-this-day), on-this-day publisher, S3 on-this-day/v1/all.json artifact.
Current implementation:
  backend/on-this-day/main.go
  backend/on-this-day/internal/usecase/usecase.go
  backend/on-this-day/internal/adapter/artifacts/artifacts.go
  backend/on-this-day/cmd/publisher/main.go
```

> **iOS note:** EPAC-1933 removes the Home feed presentation and iOS runtime dependency for this data.
> The backend endpoint and artifact publisher remain listed because their removal is tracked outside this app change.

> **Adapter note:** EPAC-1916 moves API reads to `on-this-day/v1/all.json`. The publisher remains the only Postgres reader and computes the current-MP / bill / vote ranking order at publish time.

---

### GetEstimates

```
Actor: Backend API caller
Goal: Read Main Estimates rows by fiscal year or organization.
Inputs: Fiscal year, optional organization id.
Outputs: EstimatesResponse with GC InfoBase-derived Estimate rows.
Entities / values: EstimateOrg.
Ports: EstimatesReader.
Primary adapters: estimates Lambda (GET /api/v1/estimates, GET /api/v1/estimates/{org_id}), estimates publisher, S3 estimates/v1 artifacts.
Current implementation:
  backend/estimates/main.go
  backend/estimates/internal/usecase/usecase.go
  backend/estimates/internal/adapter/artifacts/artifacts.go
  backend/estimates/cmd/publisher/main.go
```

> **Adapter note:** EPAC-1916 moves API reads to `estimates/v1/all.json` and `estimates/v1/by-org/{org-id}.json`. The publisher remains the only Postgres reader for the Main Estimates table.

---

### GetRidingBoundary

```
Actor: Backend API caller
Goal: Read a simplified federal riding boundary by slug.
Inputs: Riding slug.
Outputs: RidingBoundary GeoJSON payload with source metadata.
Entities / values: RidingBoundary.
Ports: RidingBoundaryRepository.
Primary adapters: riding-boundary Lambda (GET /api/v1/ridings/{slug}/boundary), riding-boundary publisher, S3 ridings/v1 artifacts.
Current implementation:
  backend/riding-boundary/main.go
  backend/riding-boundary/cmd/publisher/main.go
```

> **Adapter note:** EPAC-1916 moves provider fetch and Douglas-Peucker simplification to the publisher. The Lambda reads `ridings/v1/boundary/{slug}.json`; `ridings/v1/index.json` lists all published slugs.
> **iOS note:** EPAC-1935 removed the MP-profile riding-boundary map surface, so the iOS app no longer calls this use case.

---

### GetHouseCalendar

```
Actor: Legacy backend API caller
Goal: Serve the existing RFC 5545 House sitting calendar artifact.
Inputs: None.
Outputs: Raw text/calendar response.
Entities / values: CalendarEntry.
Ports: CalendarArtifactRepository.
Primary adapters: calendar Lambda (GET /api/v1/calendar/house.ics), S3 calendar/v1/house.ics artifact.
Current implementation:
  backend/calendar/main.go
```

> **Adapter note:** The iOS app no longer exposes this hosted calendar feed as of EPAC-1937.

---

### GetAppConfig

```
Actor: Backend API caller
Goal: Fetch backend-provided minimum supported app version and feature flags.
Inputs: None.
Outputs: AppConfig.
Entities / values: AppConfig.
Ports: AppConfigRepository.
Primary adapters: config Lambda (GET /api/v1/config), config publisher, S3 config/v1/app.json artifact.
Current implementation:
  backend/config/main.go
  backend/config/cmd/publisher/main.go
```

> **Adapter note:** EPAC-1916 introduces the config artifact as `config/v1/app.json`. Environment-specific config should be isolated by the deployment's artifact bucket or prefix rather than by changing the API response shape.

---

### FollowTopic

```
Actor: User (iOS app, Topics tab or notifications prompt)
Goal: Opt in to receive notifications when Parliament debates a followed topic.
Inputs: Topic selection, notification granularity (every speech / summary only).
Outputs: Updated followed-topics list; registration sent to backend.
Entities / values: ParliamentaryTopic, DeviceSubscription.
Ports: TopicPreferenceStore, DeviceRegistrationClient.
Primary adapters: TopicsView, TopicFollowStore. The backend device registration route was retired by EPAC-1921.
Current implementation:
  ios/epac/Views/Topics/TopicsView.swift
  ios/epac/Util/TopicFollowStore.swift
```

> **Domain contract:** Topic IDs come from `shared/topic-taxonomy/parliamentary_topics.json`.

---

### MatchParliamentaryTopics

```
Actor: System (Backend / iOS)
Goal: Match Hansard subject titles and related text against the canonical parliamentary topic taxonomy.
Inputs: Free-form debate or speech title text.
Outputs: Zero or more canonical topic IDs in taxonomy order.
Entities / values: ParliamentaryTopic.
Ports: None.
Primary adapters: Shared topic taxonomy parser.
Current implementation:
  shared/topic-taxonomy/parliamentary_topics.json
  ios/epac/Model/ParliamentaryTopic.swift
```

> **Policy notes:** Keywords are product policy, shared across iOS and backend adapters. Retain the existing `naturalresources` topic as canonical. Its stable ID is already stored in iOS user preferences and used by natural-resource context features, so the backend must adopt that same ID and keyword set instead of dropping it.

---

### RegisterDeviceForNotifications

> Retired in EPAC-1921. The backend `device-register` Lambda and `/api/v1/device/register` route are removed from desired state. Re-introduction would require a new implementation ticket with an explicit backend registration boundary.

---

### ViewMemberSpeechFeed

> Retired in EPAC-1934. The iOS member profile no longer exposes a per-member
> speech feed, topic chips, or backend-loaded speech stats. Backend
> member-speeches artifacts and Lambdas remain only as legacy teardown surface
> until a separate backend cleanup ticket removes them.

---

### ViewMemberVoteFeed

```
Actor: User (iOS app, Members tab -> member profile)
Goal: Browse a member's recorded voting history.
Inputs: Member ID, page number.
Outputs: Paginated list of recorded votes with ballot, date, bill number, summary, and source URL.
Entities / values: RecordedVote, ParliamentMember, MemberID.
Ports: MemberContentRepository.
Primary adapters: MemberVotingHistoryView, MemberVotingRecordView, member-votes Lambda (GET /api/v1/members/{id}/votes), S3ArtifactMemberContentRepository, member-votes-publisher.
Current implementation:
  ios/epac/Views/Members/MemberVotingHistoryView.swift
  ios/epac/Views/Members/MemberVotingRecordView.swift
  backend/member-votes/main.go
  backend/member-content/content.go
  backend/member-votes-publisher/main.go
```

---

### FetchLiveParliamentStatus

> Retired in EPAC-1921. The backend `live-status` Lambda and `/api/v1/live` route are removed from desired state. The historical architecture note remains in `docs/architecture/live-status-backend-epac165.md`.

---

### IngestHansard

```
Actor: Scheduler (EventBridge, daily after Parliament publishes)
Goal: Fetch the latest Hansard XML from ourcommons.ca, parse interventions, and write canonical speech records to the database.
Inputs: Target parliament number, session number, sitting date (EventBridge payload).
Outputs: Upserted speech records in speeches table; structured JSON log on stderr.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage.
Ports: HansardRepository, Clock.
Primary adapters: daily-fetch Lambda, loader Lambda, PostgreSQL speeches table (intervention_id PK), hansard-backfill Lambda (historical).
Current implementation:
  backend/daily-fetch/internal/usecase/usecase.go
  backend/daily-fetch/internal/adapter/postgres/postgres.go
  backend/daily-fetch/main.go
  backend/loader/main.go
  backend/hansard-backfill/main.go (historical ingestion)
  backend/migrations/           (schema migration SQL)
```

> Schema rationale: `docs/architecture/parsed-speech-schema-epac464.md`.
> All content must trace to authoritative source data. No AI-generated or summarized text is persisted.

---

### NotifyTopicFollowers

> Retired in EPAC-1921. The backend `topic-notifier` Lambda is removed from the Go workspace and no longer generated from the shared topic taxonomy.

---

### GenerateManifest

```
Actor: CI pipeline (GitHub Actions, post-artifact-publish step)
Goal: Produce a deterministic manifest.json listing every artifact in the S3 bucket for publisher and backend operational validation.
Inputs: S3 bucket name.
Outputs: manifest.json written to s3://<bucket>/manifest.json with Cache-Control: public, max-age=60; fails if any artifact is missing required x-amz-meta-content-hash-sha256 metadata.
Entities / values: Manifest, ManifestEntry.
Ports: ArtifactStore.
Primary adapters: S3ArtifactStore (AWS SDK v2 — ListObjectsV2 + HeadObject + PutObject), cmd/generate-manifest CLI entrypoint.
Current implementation:
  backend/manifest/manifest.go     (entities + ArtifactStore port)
  backend/manifest/generate.go     (use case + Generate convenience fn)
  backend/manifest/s3.go           (S3ArtifactStore adapter)
  backend/manifest/cmd/generate-manifest/main.go
```

> **Schema contract:** `backend/manifest/README.md` is the backend artifact publishing contract. Bumping `schema_version` requires coordinated changes to backend publishers and manifest validation.

---

### PublishStatisticsArtifacts

```
Actor: Scheduler (GitHub Actions artifact publisher) / Developer (manual run)
Goal: Fetch authoritative government statistics sources, compose JSON snapshots, and publish CDN-ready S3 artifacts.
Inputs: Pipeline name, upstream source data, artifacts bucket, publish cadence.
Outputs: `statistics/v1/<pipeline-name>/<dataset>.json` objects with SHA-256 content-hash metadata.
Entities / values: ArtifactKey.
Ports: StatisticsSink, Clock.
Primary adapters: statistics pipeline CLIs, statistics_artifacts.py, boto3 S3 client.
Current implementation:
  backend/cpi-statistics/cpi_statistics.py
  backend/fiscal-monitor/fiscal_monitor.py
  backend/cpp-oas-statistics/cpp_oas_statistics.py
  backend/ei-statistics/ei_statistics.py
  backend/vac-statistics/vac_statistics.py
  backend/student-finance-statistics/student_finance_statistics.py
  backend/corrections-statistics/corrections_statistics.py
  backend/transport-safety-statistics/transport_safety_statistics.py
  backend/statistics_artifacts.py
```

> Boundary rule: pipeline parsers own authoritative-source fetching and JSON composition; `statistics_artifacts.py` owns S3 keys, uploads, cache headers, and content-hash metadata.

---

### BuildHansardSubjectsIndex

```
Actor: Scheduler (GitHub Actions artifact publisher)
Goal: Publish a compact JSON index of searchable Hansard subjects for iOS pre-warming.
Inputs: Date window, parliament-count window (default current parliament plus previous two).
Outputs: Deterministic subjects JSON artifact with schema version, generation time, window, and subject rows.
Entities / values: Hansard, SubjectOfBusiness.
Ports: SubjectsRepository, Clock.
Primary adapters: hansard-subjects-index CLI, PostgreSQL speeches table.
Current implementation:
  backend/hansard-subjects-index/application/usecase.go
  backend/hansard-subjects-index/repository/postgres.go
```

> Boundary rule: artifact publishing, S3, CloudFront, and manifest concerns stay outside the use case; the use case only reads source subjects and emits deterministic JSON.

---

## Boundary Check

Run locally to verify inward files do not import framework types:

```bash
scripts/check-boundaries.sh
```

See that file for exit codes and per-path skip notes.

## Provincial Hansard adapters

The application layer depends on `HansardRepository`. Runtime dispatch is owned
by `JurisdictionRoutedHansardRepository`, which maps each `Jurisdiction` to one
adapter. Provincial rows stay TODO until the province-specific implementation
issue lands.

| Jurisdiction | Adapter file | Status |
|---|---|---|
| Federal | `ios/epac/Data/Repositories/SwiftDataHansardRepository.swift` | Registered in `JurisdictionRoutedHansardRepository` at app startup. |
| Alberta | `ios/epac/Data/Adapters/Hansard/AlbertaHansardAdapter.swift` | TODO — EPAC-613. |
| British Columbia | `ios/epac/Data/Adapters/Hansard/BritishColumbiaHansardAdapter.swift` | TODO — EPAC-680. |
| Manitoba | `ios/epac/Data/Adapters/Hansard/ManitobaHansardAdapter.swift` | TODO — EPAC-786. |
| Nova Scotia | `ios/epac/Data/Adapters/Hansard/NovaScotiaHansardAdapter.swift` | TODO — EPAC-793. |
| Quebec | `ios/epac/Data/Adapters/Hansard/QuebecHansardAdapter.swift` | TODO — EPAC-936. |
| Saskatchewan | `ios/epac/Data/Adapters/Hansard/SaskatchewanHansardAdapter.swift` | Registered in `JurisdictionRoutedHansardRepository` at app startup. |

Boundary rule: files matching
`ios/epac/Data/Adapters/Hansard/**/*Adapter.swift` must not import `SwiftUI`,
`SwiftData`, or `UIKit`. If the check fails, move UI or persistence concerns to
a Repository or ViewModel layer.

### What "inward" means for epac today

The boundary between application policy and delivery adapters does not have fully isolated directories yet (those are being created by EPAC-1741, EPAC-1742, EPAC-1743). Until those tickets land, the boundary is conceptual and documented here:

| Boundary path | Status | Creating issue |
|---|---|---|
| `ios/epac/Application/` — Swift use-case types free of SwiftUI/SwiftData | Not yet created | EPAC-1742 |
| `ios/epac/Domain/` — pure Swift domain models | Not yet created | EPAC-1741 |
| `backend/*/application/` — Go use-case types free of Lambda/pgx | Added incrementally as backend services gain explicit application boundaries | EPAC-1743 |

The boundary-check script reports any violations it can verify today and prints a skip notice with the owning issue for paths that do not yet exist.
