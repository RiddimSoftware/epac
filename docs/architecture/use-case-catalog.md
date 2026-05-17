# epac Use-Case Catalog

> **Catalog update rule:** Any PR that creates, renames, removes, or materially changes a cataloged use case must update the relevant entry in this file in the same PR. "Material change" means a new input, output, port, or actor — not internal refactoring of the adapter layer.

This catalog describes application policy (what epac does) without importing or requiring SwiftUI, SwiftData, UIKit, Lambda event types, APNs, `pgx`, or URLSession types. Delivery adapters are listed under *Primary adapters* as named artifacts, not as architectural definitions.

For the Clean Architecture shape this catalog assumes, see [`docs/architecture/`](.) and the org guidance at `/Users/sunny/code/skills/arch-team/references/clean-architecture.md`.

---

## Entities / Value Objects

| Name | Description |
|---|---|
| `Hansard` | A single sitting's parsed debate record, keyed by sitting date. |
| `SubjectOfBusiness` | A labelled section within a Hansard (e.g., "Oral Questions"). |
| `SpeechMessage` | One speaker's intervention within a subject, with text, word count, and member reference. |
| `ParliamentMember` | An elected Member of Parliament with riding, party, and contact info. |
| `ParliamentaryTopic` | A named theme (e.g., "Housing") with associated keyword matchers. |
| `DeviceSubscription` | An APNs token plus the topic/bill/member preferences registered for that device. |
| `LiveParliamentStatus` | A snapshot of whether the House is currently sitting, what business is in progress, and whether a division is active. |
| `Manifest` | The root manifest.json document: schema version, generation timestamp, and sorted artifact entries. |
| `ManifestEntry` | Metadata for one S3 artifact: key, size, SHA-256 hash, ETag, last-modified, and per-artifact schema version. |

## Ports

| Name | Direction | Description |
|---|---|---|
| `HansardRepository` | outbound | Load and store parsed Hansard records. |
| `MemberRepository` | outbound | Resolve member records by ID, name, or riding. |
| `TopicPreferenceStore` | outbound | Read and persist a device's followed topics and granularity settings. |
| `DeviceRegistrationClient` | outbound | Persist a device's APNs token and subscription preferences to the backend. |
| `LiveParliamentStatusFetching` | outbound | Fetch the current House sitting status from the backend cache. |
| `NotificationDelivering` | outbound | Send push notifications to subscribed devices via APNs. |
| `SubjectsRepository` | outbound | Read Hansard subject records for artifact generation. |
| `Clock` | outbound | Provide the current timestamp for scheduling and cache-freshness checks. |
| `ArtifactStore` | outbound | List artifact keys and metadata from object storage; write manifest.json back. |

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
Primary adapters: SittingCalendarViewModel, SittingCalendarView, Fetch (calendar XML download from ourcommons.ca), LiveParliamentService.
Current implementation:
  ios/epac/Views/Calendar/SittingCalendarViewModel.swift
  ios/epac/Views/Calendar/SittingCalendarView.swift
  ios/epac/Views/Calendar/SittingView.swift
  ios/epac/Views/Calendar/SittingViewModel.swift
  ios/epac/Util/LiveParliamentService.swift
  ios/epac/Model/Fetch.swift (downloadCalendar)
```

---

### ReadHansardSpeech

```
Actor: User (iOS app, foreground)
Goal: Read a Hansard debate as a group-chat conversation thread.
Inputs: Sitting date, subject-of-business selection.
Outputs: Ordered list of SpeechMessages with speaker names, photos, and text; resume position; replay state.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage, ParliamentMember.
Ports: HansardRepository, MemberRepository, Clock.
Primary adapters: SpeechViewModel, SpeechView, SpeakerImageViewModel, MemberDownloadCoordinator, Fetch (downloadHansard), SwiftData (Hansard / SubjectOfBusiness / Message models).
Current implementation:
  ios/epac/Views/Chat/SpeechViewModel.swift
  ios/epac/Views/Chat/SpeechView.swift
  ios/epac/Views/Chat/SpeakerImageViewModel.swift
  ios/epac/Views/Calendar/MemberDownloadCoordinator.swift
  ios/epac/Model/Fetch.swift (downloadHansard)
  ios/epac/Model/Model.swift (Hansard, SubjectOfBusiness, Message)
```

> **Boundary note:** `SpeechViewModel` currently holds SwiftData `ModelContext` references, which will be isolated when EPAC-1742 introduces the `SearchHansard` use case boundary. Until then the adapter boundary sits at the ViewModel/View seam.

---

### SearchHansard

```
Actor: User (iOS app, foreground) or User (iOS app, Spotlight)
Goal: Find Hansard debates, members, bills, or votes matching a text query.
Inputs: Query string, optional entity-type filter.
Outputs: Ranked list of matching results with entity type, title, and navigation hint.
Entities / values: Hansard, SubjectOfBusiness, ParliamentMember.
Ports: HansardRepository, MemberRepository.
Primary adapters (backend): search Lambda (GET /api/v1/search), PostgreSQL tsvector index.
Primary adapters (iOS): SearchViewModel, SearchView, NetworkService.
Current implementation:
  ios/epac/Views/Search/SearchViewModel.swift
  ios/epac/Views/Search/SearchView.swift
  ios/epac/Util/NetworkService.swift
  backend/search/main.go
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

### FollowTopic

```
Actor: User (iOS app, Topics tab or notifications prompt)
Goal: Opt in to receive notifications when Parliament debates a followed topic.
Inputs: Topic selection, notification granularity (every speech / summary only).
Outputs: Updated followed-topics list; registration sent to backend.
Entities / values: ParliamentaryTopic, DeviceSubscription.
Ports: TopicPreferenceStore, DeviceRegistrationClient.
Primary adapters: TopicsView, TopicFollowStore, NotificationManager, device-register Lambda.
Current implementation:
  ios/epac/Views/Topics/TopicsView.swift
  ios/epac/Util/TopicFollowStore.swift
  ios/epac/Util/NotificationManager.swift
  backend/device-register/main.go
  backend/device-register/application/usecase.go
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
  backend/topic-notifier/topic_taxonomy_gen.go
  backend/search/topic_taxonomy_gen.go
  ios/epac/Model/ParliamentaryTopic.swift
```

> **Policy notes:** Keywords are product policy, shared across iOS and backend adapters. Retain the existing `naturalresources` topic as canonical. Its stable ID is already stored in iOS user preferences and used by natural-resource context features, so the backend must adopt that same ID and keyword set instead of dropping it.

---

### RegisterDeviceForNotifications

```
Actor: iOS system (APNs token delivery) / User (notification permission prompt)
Goal: Persist the device's APNs token and current subscription preferences so the backend can deliver push notifications.
Inputs: APNs device token, current topic/bill/member subscription payload.
Outputs: Upserted DeviceSubscription record (backend); stored token in device keychain/UserDefaults.
Entities / values: DeviceSubscription.
Ports: DeviceRegistrationClient.
Primary adapters: NotificationManager (token receipt), NotificationPreferenceStore, device-register Lambda (POST /api/v1/device/register), PostgreSQL device_subscriptions table.
Current implementation:
  ios/epac/Util/NotificationManager.swift
  ios/epac/Util/NotificationPreferenceStore.swift
  backend/device-register/main.go
  backend/device-register/application/usecase.go   ← clean use-case boundary exists here
  backend/device-register/repository/postgres.go
```

> **Note:** `backend/device-register/application/usecase.go` is the only use-case type currently expressed as an explicit Go struct with injected ports. This is the reference pattern for future backend use cases (EPAC-1743).

---

### ViewMemberSpeechFeed

```
Actor: User (iOS app, Members tab → member profile)
Goal: Browse a member's paginated speech history, optionally filtered by topic.
Inputs: Member ID, page number, optional topic filter.
Outputs: Paginated list of SpeechMessages with stats (total speeches, average word count, top topic).
Entities / values: SpeechMessage, ParliamentMember, ParliamentaryTopic.
Ports: HansardRepository, MemberRepository.
Primary adapters: MemberSpeechFeedViewModel, MemberSpeechFeedView, MemberSpeechService, member-speeches Lambda (GET /api/v1/members/{id}/speeches).
Current implementation:
  ios/epac/Views/Members/MemberSpeechFeedViewModel.swift
  ios/epac/Views/Members/MemberSpeechFeedView.swift
  ios/epac/Util/MemberSpeechService.swift
  backend/member-speeches/main.go
```

---

### FetchLiveParliamentStatus

```
Actor: Scheduler (EventBridge, every 2 minutes during sitting windows)
Goal: Provide a fresh snapshot of whether the House is currently sitting and what business is in progress.
Inputs: None (EventBridge scheduled event).
Outputs: LiveParliamentStatus persisted to PostgreSQL live_session table.
Entities / values: LiveParliamentStatus.
Ports: Clock.
Primary adapters: live-status Lambda (EventBridge ingest + GET /api/v1/live), PostgreSQL live_session table (singleton).
Current implementation:
  backend/live-status/main.go
```

> Architecture rationale: `docs/architecture/live-status-backend-epac165.md`.
> iOS client removed in EPAC-1919 (Aurora teardown). Re-introduction tracked in EPAC-1928.

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
  backend/daily-fetch/main.go
  backend/loader/main.go
  backend/hansard-backfill/main.go (historical ingestion)
  backend/migrations/           (schema migration SQL)
```

> Schema rationale: `docs/architecture/parsed-speech-schema-epac464.md`.
> All content must trace to authoritative source data. No AI-generated or summarized text is persisted.

---

### NotifyTopicFollowers

```
Actor: Scheduler (EventBridge, daily ~02:00 UTC after Hansard publishes)
Goal: Send APNs push notifications to all devices that follow a topic debated in today's Hansard.
Inputs: Sitting date, ingested speeches from the speeches table.
Outputs: APNs pushes delivered to matched device tokens; delivery errors logged.
Entities / values: ParliamentaryTopic, DeviceSubscription, SpeechMessage.
Ports: HansardRepository, TopicPreferenceStore, NotificationDelivering, Clock.
Primary adapters: topic-notifier Lambda, PostgreSQL device_subscriptions table, APNs HTTP/2 sender, TopicNotificationScheduler (iOS local fallback), MemberNotificationScheduler (iOS, member-specific alerts).
Current implementation:
  backend/topic-notifier/main.go
  ios/epac/Util/TopicNotificationScheduler.swift   ← local fallback only
  ios/epac/Util/MemberNotificationScheduler.swift  ← member-activity local alerts
  ios/epac/Util/NotificationManager.swift          ← remote notification receiver
```

> **Dependency:** Uses `MatchParliamentaryTopics` and the canonical taxonomy rather than an adapter-local copy.

---

### GenerateManifest

```
Actor: CI pipeline (GitHub Actions, post-artifact-publish step)
Goal: Produce a deterministic manifest.json listing every artifact in the S3 bucket so the iOS app can diff against it and download only changed files.
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

> **Schema contract:** `backend/manifest/README.md` is the only shared contract between the publisher (CI) and the consumer (iOS app). Bumping `schema_version` requires coordinated changes to both sides.

---

### BuildHansardSubjectsIndex

```
Actor: Scheduler (GitHub Actions artifact publisher)
Goal: Publish a compact JSON index of searchable Hansard subjects for iOS pre-warming.
Inputs: Date window, parliament-count window (default current parliament plus previous two).
Outputs: Deterministic subjects JSON artifact with schema version, generation time, window, and subject rows.
Entities / values: Hansard, SubjectOfBusiness.
Ports: SubjectsRepository, Clock.
Primary adapters: hansard-subjects-index CLI, PostgreSQL speeches table, publish-artifacts workflow.
Current implementation:
  backend/hansard-subjects-index/application/usecase.go
  backend/hansard-subjects-index/repository/postgres.go
  .github/workflows/publish-artifacts.yml
```

> Boundary rule: artifact publishing, S3, CloudFront, and manifest concerns stay in the GitHub Actions workflow; the use case only reads source subjects and emits deterministic JSON.

---

## Boundary Check

Run locally to verify inward files do not import framework types:

```bash
scripts/check-boundaries.sh
```

See that file for exit codes and per-path skip notes.

### What "inward" means for epac today

The boundary between application policy and delivery adapters does not have fully isolated directories yet (those are being created by EPAC-1741, EPAC-1742, EPAC-1743). Until those tickets land, the boundary is conceptual and documented here:

| Boundary path | Status | Creating issue |
|---|---|---|
| `ios/epac/Application/` — Swift use-case types free of SwiftUI/SwiftData | Not yet created | EPAC-1742 |
| `ios/epac/Domain/` — pure Swift domain models | Not yet created | EPAC-1741 |
| `backend/*/application/` — Go use-case types free of Lambda/pgx | Exists in `device-register` only | EPAC-1743 |

The boundary-check script reports any violations it can verify today and prints a skip notice with the owning issue for paths that do not yet exist.
