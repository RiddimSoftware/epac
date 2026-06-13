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
| `Senator` | An appointed Senator with province, declared caucus affiliation, Senate profile URL, and appointment facts when available. |
| `SenateAppointment` | Appointment facts for a Senator: date, appointing prime minister, represented province, declared affiliation, and Privy Council Office source URL. |
| `Sitting` | A House sitting date with Parliament/session metadata and source URL. |
| `EPetition` | An e-petition submitted to the House of Commons with signatures, sponsor, deadline, and optional government response. |
| `PetitionGovernmentResponse` | The government's official written response tabled in the House of Commons for a qualified petition. |
| `Bill` | A Parliament of Canada bill with number, title, stage, sponsor, Royal Assent date when available, and LEGISinfo source URL. |
| `BillVersion` | Backend-only bill publication/version row with source links for text, PDF, and XML artifacts. |
| `BillAmendment` | Backend-only House or committee amendment record associated with a bill and chamber stage. |
| `PBOCosting` | Backend-only Parliamentary Budget Officer costing link associated with a bill. |
| `MemberBiography` | Parliament.ca biography details for an MP profile, including service periods, roles, education, professional background, source URL, and summary text where available. |
| `MemberAttendanceRecord` | Backend-only House vote/attendance row for an MP, with vote date, subject, result, and ballot where available. |
| `PMBSponsorship` | Backend-only private member's bill sponsorship or seconding relationship for an MP. |
| `ParliamentaryTopic` | A named theme (e.g., "Housing") with associated keyword matchers. |
| `OCLSubjectMatter` | An Office of the Commissioner of Lobbying subject-matter code used on communication reports and registrations. |
| `EpacTopicSlug` | The stable epac topic identifier used to group parliamentary and lobbying records. |
| `LobbyingByTopicResult` | Backend-only paged lobbying result set for an epac topic, including source citation metadata. |
| `BillLobbyingContext` | Bill-level lobbying cross-reference result with communication counts by organization and subject matter. |
| `LobbyingSubjectMatch` | Backend-only link between a bill subject tag, high-confidence epac topic mapping, and OCL subject-matter code. |
| `OrganizationCommunicationCount` | Backend-only count of OCL communication reports grouped by organization name. |
| `Minister` | Backend-only cabinet minister identity resolved by House of Commons member ID and name. |
| `Portfolio` | A cabinet portfolio title held by a minister during a known date period. |
| `MinisterTenure` | Date-window value for a minister's cabinet service, used when portfolio boundaries are incomplete. |
| `LobbyingByPortfolio` | Backend-only minister lobbying response grouped by portfolio period or cabinet tenure fallback. |
| `CabinetLobbyingSummary` | Backend-only cabinet overview row ranking a minister by OCL communication count. |
| `MPLobbyingSummary` | Precomputed MP lobbying exposure summary for a parliament, quarter, and window. |
| `LobbyingTimelineEntry` | Source-cited OCL communication row attributed to an MP for exposure timelines. |
| `LobbyingSubjectDistribution` | Per-subject communication count row for MP lobbying exposure charts. |
| `MPLobbyingTopOrganization` | MP-level lobbying dashboard row for top-ranked organizations and communication counts. |
| `MPLobbyingCohortComparison` | Party and national cohort comparison metrics for an MP exposure summary. |
| `LobbyingCohortAverage` | Build-time party or national average communication count for a parliament. |
| `DeviceSubscription` | An APNs token plus the topic/bill/member preferences registered for that device. |
| `PushNotificationPayload` | Backend-only internal push payload carrying required live-vote division fields and the compacted original JSON document. |
| `LiveVoteNotification` | Backend-only display-ready push notification value with neutral title/body copy and source division identifiers for APNs delivery. |
| `RoyalAssentNotification` | iOS notification content value used when a followed bill transitions to Royal Assent during app or background refresh. |
| `DispatchResult` | Backend-only push dispatch outcome counts for subscription fan-out, successful deliveries, and failed delivery attempts. |
| `LiveParliamentStatus` | A snapshot of whether the House is currently sitting, what business is in progress, and whether a division is active. |
| `OnThisDayItem` | A backend-only historical Parliament moment for the same calendar day in prior years. |
| `EstimateOrg` | A GC InfoBase organization identifier and display name used to group Main Estimates rows. |
| `RidingBoundary` | A simplified federal electoral district boundary with source metadata and GeoJSON geometry. |
| `CalendarEntry` | A House sitting day represented in the public RFC 5545 calendar feed. |
| `AppConfig` | Backend-provided app version and feature-flag settings. |
| `ArtifactKey` | A published object key used by backend artifact publishers, such as `members/v1/all.json`. |
| `Manifest` | The root manifest.json document: schema version, generation timestamp, and sorted artifact entries. |
| `ManifestEntry` | Metadata for one S3 artifact: key, size, SHA-256 hash, ETag, last-modified, and per-artifact schema version. |
| `HansardSearchIntervention` | Backend-only parsed Hansard intervention value used while building the SQLite FTS5 search artifact. |
| `HansardSearchManifest` | Backend-only manifest pointer for the current-session Hansard search SQLite artifact. |
| `BillsIndexManifest` | Backend-only manifest pointer for the bills relational SQLite artifact. |
| `MembersIndexManifest` | Backend-only manifest pointer for the members relational SQLite artifact. |
| `MinisterPortfolioLobbyingPeriod` | A cabinet portfolio tenure window with the OCL communications recorded while a minister held that portfolio. |
| `MinisterLobbyingCommunication` | One OCL communication row for a minister, including organization, subject matter, date, citation URL, and mandate-letter match flag. |
| `CabinetLobbyingOverview` | A cabinet-wide lobbying exposure summary with ranked ministers and most-active organizations per portfolio. |
| `CabinetLobbyingMinisterSummary` | A ranked cabinet minister communication total for the overview screen. |
| `CabinetLobbyingOrganizationSummary` | A portfolio-scoped organization communication total for the overview screen. |
| `LobbyistOrganization` | Aggregate for an OCL client/organization/corporation with canonical ID, type, sector, lobbyists, registrations, recent communications, subject matters, communication trend counts, and top DPOHs contacted. |
| `OrganizationSector` | OCL subject matter type description carried verbatim as the organization's sector label for profile browsing. |
| `CommunicationCount` | Current-vs-prior Parliament communication count pair used for organization profile trend display. |
| `ParliamentSession` | Date-window value defining a Parliament/session boundary for trend aggregation. |
| `CohortComparison` | Backend-only MP lobbying comparison values: MP total, party average, national average, and ratios. |

## Ports

This table records whether each cataloged port is a real Swift `protocol`, Go
`interface`, or Python `Protocol` today. Planned iOS ports are explicitly linked
to the issue that will build the missing artifact.

| Name | Stack | Direction | Artifact status | Description |
|---|---|---|---|---|
| `HansardRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/HansardRepository.swift`; conformers include `ios/epac/Data/Repositories/SwiftDataHansardRepository.swift` and `ios/epac/Data/Adapters/Hansard/JurisdictionRoutedHansardRepository.swift`. | Load and store jurisdiction-aware parsed Hansard transcripts. |
| `HansardRepository` | backend Go | outbound | Implemented: `backend/daily-fetch/internal/usecase/usecase.go`, `backend/on-this-day/internal/usecase/usecase.go`; adapters include `backend/daily-fetch/internal/adapter/postgres/postgres.go` and `backend/on-this-day/internal/adapter/artifacts/artifacts.go`. | Load and store canonical Hansard records for backend ingestion and historical-content use cases. |
| `MemberRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/MemberRepository.swift`; adapter: `ios/epac/Data/Adapters/RidingLookupMemberRepository.swift`. | Resolve member-related lookups, starting with riding lookup by postal code for FindMyMP. |
| `SittingRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/SittingRepository.swift`; adapter: `ios/epac/Data/Adapters/HansardSittingRepositoryAdapter.swift`. | List sitting dates and load transcripts for a sitting date. |
| `BillRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/BillRepository.swift`; adapter: `ios/epac/Data/Adapters/LEGISinfoBillRepository.swift`. | List current-session bills. |
| `BillRepository` | backend Go | outbound | Implemented: `backend/bills/internal/usecase/bills.go`; adapter: `backend/bills/internal/adapter/sqlite/repository.go`. | List bills and load bill-depth rows from the verified bills SQLite artifact. |
| `RecentLawQueryPort` | iOS Swift | outbound | Implemented by `ios/epac/Application/TrackRoyalAssent.swift`; adapter input is `BillRepository`. | Query current-session bills that received Royal Assent within the recent-law window. |
| `MemberRepository` | backend Go | outbound | Implemented: `backend/members/internal/usecase/members.go`; adapter: `backend/members/internal/adapter/sqlite/repository.go`. | List members and load member-profile attendance rows from the verified members SQLite artifact. |
| `MemberContentRepository` | backend Go | outbound | Implemented: `backend/member-speeches/internal/usecase/usecase.go` with adapter `backend/member-speeches/internal/adapter/artifact/artifact.go`; `backend/member-votes/main.go` has a local vote-feed interface implemented by `S3ArtifactMemberContentRepository`. | Load per-member append-only content feeds such as speeches and recorded votes. There is no iOS Swift protocol with this name today. |
| `TopicPreferenceStore` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/TopicPreferenceStore.swift`; adapter: `ios/epac/Data/Adapters/TopicFollowStoreAdapter.swift`. | Read and persist followed topic IDs as a Domain-layer port. |
| `SenatorAppointmentQueryPort` | iOS Swift | outbound | Implemented by existing `HomeFeedRepository.fetchSenators(for:)`; adapter: `ios/epac/Data/Repositories/HomeFeedSwiftDataRepository.swift` using `ios/epac/Util/SenatorsService.swift`. | Load province-filtered senator appointment context for Home and My MP surfaces. |
| `DeviceSubscriptionRepository` | backend Go | outbound | Implemented: `backend/push-notification-dispatcher/internal/usecase/dispatch_push_notification.go`; adapter: `backend/push-notification-dispatcher/internal/adapter/postgres/subscriptions.go`. | List device subscriptions eligible for the current internal notification fan-out. |
| `PushNotificationClient` | backend Go | outbound | Implemented: `backend/push-notification-dispatcher/internal/usecase/dispatch_push_notification.go`; adapter: `backend/push-notification-dispatcher/internal/adapter/apns/client.go`. | Deliver a typed push payload to a subscribed device through APNs. |
| `RoyalAssentNotificationPort` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/RoyalAssentNotificationPort.swift`; adapter: `ios/epac/Data/Adapters/LiveRoyalAssentNotificationAdapter.swift`. | Schedule notification content when a followed bill is observed to have received Royal Assent. |
| `HansardSearchProviding` | iOS Swift | outbound | Implemented: `ios/epac/Util/HansardSearchService.swift`; conformer: `BackendHansardSearchService`. | Search Hansard through the backend search endpoint from iOS presentation code. |
| `HansardSearchRepository` | backend Go | outbound | Implemented: `backend/hansard-search/internal/usecase/search_hansard.go`; adapter: `backend/hansard-search/internal/adapter/sqlitefts5/repository.go`. | Query the verified SQLite FTS5 Hansard search index. |
| `ManifestLoader` | backend Go | outbound | Implemented: `backend/hansard-search/internal/usecase/open_search_index.go`; adapter: `backend/hansard-search/internal/adapter/s3manifest/manifest_loader.go`. | Load the current Hansard search-index manifest. |
| `IndexDownloader` | backend Go | outbound | Implemented: `backend/hansard-search/internal/usecase/open_search_index.go`; adapter: `backend/hansard-search/internal/adapter/sqlitefile/index_downloader.go`. | Download and verify the current Hansard search SQLite artifact. |
| `SubjectsRepository` | backend Go | outbound | Implemented: `backend/hansard-subjects-index/application/usecase.go`; adapter: `backend/hansard-subjects-index/repository/postgres.go`. | Read Hansard subject records for artifact generation. |
| `Clock` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/Ports.swift`; conformer: `SystemClock`. | Provide the current timestamp for iOS use cases. |
| `Clock` | backend Go | outbound | Implemented: `backend/daily-fetch/internal/usecase/usecase.go`, `backend/hansard-subjects-index/application/usecase.go`; conformers include `systemClock` and `SystemClock`. | Provide the current timestamp for backend scheduling and cache-freshness checks. |
| `ArtifactStore` | backend Go | outbound | Implemented: `backend/manifest/manifest.go`; adapter: `backend/manifest/s3.go`. | List artifact keys, read object metadata, and write manifest.json back to object storage. |
| `EstimatesReader` | backend Go | outbound | Implemented: `backend/estimates/internal/usecase/usecase.go`; adapters include `backend/estimates/internal/adapter/artifacts/artifacts.go` and `backend/estimates/internal/adapter/postgres/postgres.go`. | Fetch published Main Estimates rows by fiscal year, organization, or full artifact export. |
| `HansardXMLSource` | backend Go | outbound | Implemented: `backend/hansard-search-index/internal/usecase/usecase.go`; adapter: `backend/hansard-search-index/internal/adapter/ourcommons/source.go`. | Fetch authoritative ourcommons.ca Hansard XML by parliament, session, and sitting number. |
| `HansardParser` | backend Go | outbound | Implemented: `backend/hansard-search-index/internal/usecase/usecase.go`; adapter: `backend/hansard-search-index/internal/adapter/ourcommons/parser.go`. | Parse Hansard XML into intervention and paragraph values without coupling the use case to `encoding/xml`. |
| `IndexBuilder` | backend Go | outbound | Implemented: `backend/hansard-search-index/internal/usecase/usecase.go`; adapter: `backend/hansard-search-index/internal/adapter/sqlitefts5/builder.go`. | Build and self-check a local SQLite FTS5 index from parsed interventions. |
| `IndexUploader` | backend Go | outbound | Implemented: `backend/hansard-search-index/internal/usecase/usecase.go`; adapter: `backend/hansard-search-index/internal/adapter/s3/s3.go`. | Upload the SQLite search index artifact. |
| `ManifestWriter` | backend Go | outbound | Implemented: `backend/hansard-search-index/internal/usecase/usecase.go`; adapter: `backend/hansard-search-index/internal/adapter/s3/s3.go`. | Write the search-index manifest pointer. |
| `LobbyistOrganizationRepository` | backend Go | outbound | Implemented: `backend/lobbying/application/aggregate.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`; build-time aggregation adapter: `backend/lobbying-index/internal/adapter/sqlite/aggregator.go`. | Load lobbyist organization aggregates independent of HTTP delivery. |
| `OrganizationDirectoryQuery` | backend Go | outbound | Implemented: `backend/lobbying/application/aggregate.go`; build-time adapter: `backend/lobbying-index/internal/adapter/sqlite/aggregator.go`. | Read OCL registration and communication source rows during artifact assembly. |
| `MPLobbyingRepository` | backend Go | outbound | Implemented: `backend/lobbying/application/mp_exposure.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`; build-time read-model writer: `backend/lobbying-index/internal/adapter/sqlite/mp_aggregation.go`. | Load precomputed MP lobbying summaries and paged timeline rows from the SQLite artifact. |
| `LobbyingSubjectDistributionQuery` | backend Go | outbound | Implemented: `backend/lobbying/application/mp_exposure.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Load the all-subject communication breakdown for an MP lobbying exposure response. |
| `LobbyingSubjectsRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/usecase.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Read OCL communication and registration records by mapped subject-matter code. |
| `BillSubjectsRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/bill_lobbying_context.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Read bill subject tags and the latest bill reading anchor used for bill-level lobbying context. |
| `BillLobbyingCommunicationsRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/bill_lobbying_context.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Read OCL communication rows matching mapped bill subject codes within a date window. |
| `BillLobbyingContextRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/BillLobbyingContextRepository.swift`; adapter: `ios/epac/Data/Repositories/BackendBillLobbyingContextRepository.swift`. | Load bill-level lobbying context summaries from the backend lobbying endpoint. |
| `MPLobbyingServiceProviding` | iOS Swift | outbound | Implemented: `ios/epac/Util/MPLobbyingService.swift`; conformer: `ios/epac/Util/BackendMPLobbyingService`. | Load MP lobbying dashboard payloads, including summary, timeline, subject filters, cohort comparison, and pagination settings from the backend endpoint. |
| `OCLSubjectsSource` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/usecase.go`; adapter: `backend/lobbying/internal/adapter/ocltopicmap/source.go` reading `backend/lobbying/ocl_topic_map.json`. | Resolve an epac topic slug to the OCL subject-matter codes that should be included. |
| `OCLSource` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/usecase.go`; adapter: `backend/lobbying-index/internal/adapter/ocl/fetcher.go`. | Fetch and parse OCL open-data ZIPs (communications and registrations) in-memory. |
| `MembersSource` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/usecase.go`; adapter: `backend/lobbying-index/internal/adapter/ourcommons/fetcher.go`. | Fetch and normalize active MP records from ourcommons.ca members XML. |
| `SubjectMatterSource` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/usecase.go`; adapter: `backend/lobbying-index/internal/adapter/subjects/fetcher.go`. | Fetch and parse OCL subject-matter controlled-vocabulary rows. |
| `RawTableWriter` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/usecase.go`; adapter: `backend/lobbying-index/internal/adapter/sqlite/writer.go`. | Load parsed OCL, member, and subject-matter rows into local SQLite raw tables. |
| `OrgAggregator` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/org_aggregation.go`; adapter: `backend/lobbying-index/internal/adapter/sqlite/aggregator.go`. | Run build-time SQLite aggregation to produce derived organization and subject-matter tables. |
| `LegisInfoSource` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/org_aggregation.go`; adapter: `backend/lobbying-index/internal/adapter/legisinfo/fetcher.go`. | Fetch bill metadata (reading dates, titles) from the parl.ca/legisinfo JSON API. |
| `BillContextWriter` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/org_aggregation.go`; adapter: `backend/lobbying-index/internal/adapter/sqlite/aggregator.go`. | Persist bill subject tags and reading dates into build-time SQLite tables. |
| `MinisterRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/minister_portfolio.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Load minister identity, cabinet tenure, and portfolio-period history for minister lobbying endpoints. |
| `MinisterLobbyingRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/minister_portfolio.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Read pre-baked minister communication rows from the SQLite artifact. |
| `MandateLetterRepository` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/minister_portfolio.go`; serving adapter: `backend/lobbying/internal/adapter/sqlite/repository.go`. | Read high-confidence mandate-letter policy-area topic mappings for minister lobbying cross-reference. |
| `OCLTopicMapper` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/minister_portfolio.go`; adapter: `backend/lobbying/internal/adapter/ocltopicmap/source.go`. | Resolve OCL subject-matter codes back to epac topic slugs for mandate-match flagging. |
| `PortfolioBoundaryGapLogger` | backend Go | outbound | Implemented: `backend/lobbying/internal/usecase/minister_portfolio.go`; adapter: `backend/lobbying/main.go` structured logging. | Log `portfolio_boundary_gap` warnings when portfolio-period boundaries are not safe to use. |
| `CabinetLobbyingRepository` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/CabinetLobbyingRepository.swift`; adapter: `ios/epac/Data/Repositories/BackendCabinetLobbyingRepository.swift`. | Load minister portfolio-period lobbying rows and cabinet-wide overview data from backend lobbying endpoints. |
| `TelemetryProvider` | iOS Swift | outbound | Implemented: `ios/epac/Util/Telemetry.swift`; conformers include `NoopTelemetryProvider` and `BackendTelemetryProvider`. | Record errors, events, performance spans, and opaque payloads without coupling app code to a third-party SDK. Default implementation is no-op; `BackendTelemetryProvider` batches small events to `POST /api/v1/telemetry`, while `MetricKitSubscriber` emits daily metric and diagnostic payloads into this port. |
| `CohortStatisticsRepository` | backend Python | outbound | Implemented: `backend/lobbying/cohort_averages.py`; adapter: `PostgresCohortStatisticsRepository`. | Read current MP membership and per-MP lobbying totals, then persist and read precomputed cohort averages. |
| `MPLobbyingAggregator` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/mp_aggregation.go`; adapter: `backend/lobbying-index/internal/adapter/sqlite/mp_aggregation.go`. | Populate MP lobbying timeline, summary, subject-breakdown, and cohort-average read tables in the build-time SQLite artifact. |
| `CabinetSource` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/minister_prebake.go`; adapter: `backend/lobbying-index/internal/adapter/cabinet/fetcher.go`. | Scrape the current Cabinet roster and current mandate-letter topics from pm.gc.ca into typed builder rows. |
| `MinisterTableWriter` | backend Go | outbound | Implemented: `backend/lobbying-index/internal/usecase/minister_prebake.go`; adapter: `backend/lobbying-index/internal/adapter/sqlite/minister_prebake.go`. | Resolve minister member IDs and pre-bake minister portfolio, mandate-topic, and denormalized communication tables in the build-time SQLite artifact. |
| `BillSource` | backend Go | outbound | Implemented: `backend/bills-indexer/internal/usecase/usecase.go`; adapter: `backend/bills-indexer/internal/adapter/legisinfo/fetcher.go`. | Fetch LEGISinfo bill detail, publication/version links, amendments, and PBO costing references for the relational bills artifact. |
| `SQLiteWriter` | backend Go | outbound | Implemented: `backend/bills-indexer/internal/usecase/usecase.go`; adapter: `backend/bills-indexer/internal/adapter/sqlite/writer.go`. | Write bills, stages, events, versions, diffs, amendments, PBO costings, related links, and build metadata into `bills.db`. |
| `SQLiteUploader` | backend Go | outbound | Implemented: `backend/bills-indexer/internal/usecase/usecase.go`; adapter: `backend/bills-indexer/internal/adapter/s3/s3.go`. | Upload the bills SQLite artifact to S3 and return immutable size/hash metadata for the manifest. |
| `MembersSource` | backend Go | outbound | Implemented: `backend/members-indexer/internal/usecase/usecase.go`; adapter: `backend/members-indexer/internal/adapter/ourcommons/fetcher.go`. | Fetch House member roster details, biographies, attendance rows, and private member's bill sponsorship links for the relational members artifact. |
| `SQLiteWriter` | backend Go | outbound | Implemented: `backend/members-indexer/internal/usecase/usecase.go`; adapter: `backend/members-indexer/internal/adapter/sqlite/writer.go`. | Write members, biographies, attendance records, PMB sponsorships, and build metadata into `members.db`. |
| `SQLiteUploader` | backend Go | outbound | Implemented: `backend/members-indexer/internal/usecase/usecase.go`; adapter: `backend/members-indexer/internal/adapter/s3/s3.go`. | Upload the members SQLite artifact to S3 and return immutable size/hash metadata for the manifest. |
| `DivisionsFetching` | backend Go | outbound | Implemented: `backend/live-vote-poller/internal/usecase/poll_live_divisions.go`; adapter: `backend/live-vote-poller/internal/adapter/ourcommons/divisions_client.go`. | Fetch live parliamentary divisions from ourcommons.ca. |
| `ArtifactRepository` | backend Go | outbound | Implemented: `backend/live-vote-poller/internal/usecase/poll_live_divisions.go`; adapter: `backend/live-vote-poller/internal/adapter/artifacts/repository.go`. | Check existence and persist completed vote payload artifacts. |
| `PushDispatching` | backend Go | outbound | Implemented: `backend/live-vote-poller/internal/usecase/poll_live_divisions.go`; adapter: `backend/live-vote-poller/internal/adapter/push/dispatcher.go`. | Forward concluded division payloads to the push-notification dispatcher. |
| `PetitionGovernmentResponseQueryPort` | iOS Swift | outbound | Implemented: `ios/epac/Domain/Ports/PetitionGovernmentResponseQueryPort.swift`; adapter: `ios/epac/Data/Repositories/BackendPetitionGovernmentResponseQueryPort.swift`. | Load petition government responses from the backend endpoint. |

## Use Cases

### BrowseTodayInParliament

```
Actor: User (iOS app, foreground)
Goal: View the sitting calendar and today's scheduled subjects of business.
Inputs: Selected date (defaults to today), calendar window (visible month range).
Outputs: List of sittings with subjects.
Entities / values: Hansard, SubjectOfBusiness.
Ports: iOS Swift: `HansardRepository`.
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
Ports: iOS Swift: `HansardRepository`.
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
Goal: Browse jurisdiction-aware sitting dates available in a calendar window.
Inputs: Jurisdiction, start date, end date.
Outputs: Sitting dates.
Entities / values: Jurisdiction, Date.
Ports: iOS Swift: `HansardRepository`.
Primary adapters: SittingCalendarViewModel, SittingCalendarView, SwiftDataHansardRepository.
Current implementation:
  ios/epac/Application/BrowseHansardSitting.swift
  ios/epac/Views/Calendar/SittingCalendarViewModel.swift
  ios/epac/Data/Repositories/SwiftDataHansardRepository.swift
```

> **Boundary note:** The application policy for window filtering is no longer in `SittingCalendarViewModel`. Transcript loading stays on the on-demand sitting-reader path.

---

### ReadHansardSpeech

```
Actor: User (iOS app, foreground)
Goal: Read a Hansard debate as a group-chat conversation thread.
Inputs: Sitting date, subject-of-business selection.
Outputs: Ordered list of SpeechMessages with speaker names, photos, and text; resume position; replay state.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage, ParliamentMember.
Ports: iOS Swift: `HansardRepository`; iOS Swift planned: `MemberRepository` ([EPAC-2195](https://linear.app/riddimsoftware/issue/EPAC-2195/introduce-domain-repository-ports-for-members-bills-sittings-and-topic)).
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
Ports: backend Go: `ManifestLoader`, `IndexDownloader`, `HansardSearchRepository`; iOS Swift: `HansardSearchProviding`.
Primary adapters (backend): hansard-search Lambda startup/wiring in `backend/hansard-search`, plus the SQLite FTS5 repository adapter in `internal/adapter/sqlitefts5`.
Primary adapters (iOS): SearchViewModel, SearchView, NetworkService.
Current implementation:
  backend/hansard-search/internal/usecase/open_search_index.go
  backend/hansard-search/internal/usecase/search_hansard.go
  backend/hansard-search/internal/adapter/sqlitefts5/repository.go
  ios/epac/Views/Search/SearchViewModel.swift
  ios/epac/Views/Search/SearchView.swift
  ios/epac/Util/HansardSearchService.swift
  ios/epac/Util/NetworkService.swift
```

> **Boundary note:** The backend `SearchHansard` use case now lives in `backend/hansard-search/internal/usecase/` and depends on a `HansardSearchRepository` port implemented by the SQLite FTS5 adapter. The iOS `SearchViewModel` remains a presentation concern for the broader search UI while D3 wires the hansard-search Lambda handler to this backend policy.

---

### BuildIndex

```
Actor: Operator (manual GitHub Actions dispatch or aws lambda invoke)
Goal: Build the current-session Hansard SQLite FTS5 index and publish its manifest pointer.
Inputs: Parliament number, session number, artifact bucket, artifact prefix.
Outputs: index.sqlite and manifest.json under the configured S3 prefix.
Entities / values: HansardSearchIntervention, HansardSearchManifest, ArtifactKey.
Ports: backend Go: `HansardXMLSource`, `HansardParser`, `IndexBuilder`, `IndexUploader`, `ManifestWriter`.
Primary adapters: ourcommons.ca XML source/parser, modernc.org/sqlite FTS5 builder, AWS S3 artifact writer.
Current implementation:
  backend/hansard-search-index/main.go
  backend/hansard-search-index/internal/usecase/usecase.go
  backend/hansard-search-index/internal/domain/domain.go
  backend/hansard-search-index/internal/adapter/ourcommons/source.go
  backend/hansard-search-index/internal/adapter/ourcommons/parser.go
  backend/hansard-search-index/internal/adapter/sqlitefts5/builder.go
  backend/hansard-search-index/internal/adapter/s3/s3.go
```

> **Boundary rule:** `backend/hansard-search-index/internal/usecase/` owns the application policy and imports only standard library packages plus the local domain package. HTTP, XML decoding, SQLite, AWS SDK, and Lambda runtime wiring stay in adapters or `main.go`.

---

### IngestBills

```
Actor: Operator (manual GitHub Actions dispatch)
Goal: Build the current-session bills relational SQLite artifact and publish its manifest pointer.
Inputs: Parliament number, session number, artifact bucket, artifact prefix.
Outputs: bills.db/index.sqlite and manifest.json under the configured S3 prefix.
Entities / values: Bill, BillVersion, BillAmendment, PBOCosting, BillsIndexManifest, ArtifactKey.
Ports: backend Go: `BillSource`, `SQLiteWriter`, `SQLiteUploader`, `ManifestWriter`.
Primary adapters: LEGISinfo/parliament.ca HTTP crawler, SQLite schema writer, AWS S3 artifact writer, `data-ingestion.yml` bills-indexer job.
Current implementation:
  backend/bills-indexer/main.go
  backend/bills-indexer/internal/usecase/usecase.go
  backend/bills-indexer/internal/domain/domain.go
  backend/bills-indexer/internal/adapter/legisinfo/fetcher.go
  backend/bills-indexer/internal/adapter/sqlite/writer.go
  backend/bills-indexer/internal/adapter/s3/s3.go
```

> **Boundary rule:** `backend/bills-indexer/internal/usecase/` owns the application policy and imports only standard library packages plus the local domain package. HTTP scraping, SQLite, AWS SDK, and GitHub Actions wiring stay in adapters or `main.go`.

---

### IngestMembers

```
Actor: Operator (manual GitHub Actions dispatch)
Goal: Build the current members relational SQLite artifact and publish its manifest pointer.
Inputs: Artifact bucket, artifact prefix, optional fetch limits/full-vote toggle.
Outputs: members.db/index.sqlite and manifest.json under the configured S3 prefix.
Entities / values: ParliamentMember, MemberBiography, MemberAttendanceRecord, PMBSponsorship, MembersIndexManifest, ArtifactKey.
Ports: backend Go: `MembersSource`, `SQLiteWriter`, `SQLiteUploader`, `ManifestWriter`.
Primary adapters: ourcommons.ca member-profile crawler, SQLite schema writer, AWS S3 artifact writer, `data-ingestion.yml` members-indexer job.
Current implementation:
  backend/members-indexer/main.go
  backend/members-indexer/internal/usecase/usecase.go
  backend/members-indexer/internal/domain/domain.go
  backend/members-indexer/internal/adapter/ourcommons/fetcher.go
  backend/members-indexer/internal/adapter/sqlite/writer.go
  backend/members-indexer/internal/adapter/s3/s3.go
```

> **Boundary rule:** `backend/members-indexer/internal/usecase/` owns the application policy and imports only standard library packages plus the local domain package. HTTP scraping, SQLite, AWS SDK, and GitHub Actions wiring stay in adapters or `main.go`.

---

### FindMyMP

```
Actor: User (iOS app, onboarding or settings)
Goal: Identify the user's Member of Parliament by postal code and save the result for the Home feed.
Inputs: Postal code string.
Outputs: Matched ParliamentMember (or not-found); persisted "my MP" preference.
Entities / values: ParliamentMember.
Ports: iOS Swift: `MemberRepository`.
Primary adapters: PostalCodeViewModel, PostalCodeSetupView, MyMPView, RidingLookupMemberRepository wrapping RidingLookupService (calls represent.opennorth.ca), TopicFollowStore (persists myMPMemberId).
Current implementation:
  ios/epac/Domain/Ports/MemberRepository.swift
  ios/epac/Data/Adapters/RidingLookupMemberRepository.swift
  ios/epac/Data/Adapters/RidingLookupService.swift
  ios/epac/Views/MyMP/PostalCodeViewModel.swift
  ios/epac/Views/MyMP/PostalCodeSetupView.swift
  ios/epac/Views/MyMP/MyMPView.swift
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
Ports: iOS Swift planned: `MemberRepository` ([EPAC-2195](https://linear.app/riddimsoftware/issue/EPAC-2195/introduce-domain-repository-ports-for-members-bills-sittings-and-topic)). Backend Go: `MemberRepository`.
Primary adapters: members Lambda (GET /api/v1/members), SQLite query adapter, S3 manifest/index downloader, members-publisher/indexer S3 artifact job, S3 members/v1 artifacts, iOS Fetch (ourcommons.ca member XML parsing).
Current implementation:
  backend/members/main.go
  backend/members/internal/usecase/members.go
  backend/members/internal/adapter/sqlite/repository.go
  backend/members/internal/adapter/s3/manifest_loader.go
  backend/members/internal/adapter/s3/index_downloader.go
  backend/members-publisher/main.go
```

> **Adapter note:** EPAC-2260 moves the backend API path from `members/v1/all.json` to the manifest-selected SQLite artifact in S3. The use case depends on the backend `MemberRepository` port; AWS, local `/tmp` files, and `database/sql` stay in adapters.

---

### GetMemberProfile

```
Actor: User (iOS app, Members tab -> MP profile) / Backend API caller
Goal: Load one member profile with attendance, biography, and private member's bill sponsorship rows when the members SQLite artifact includes them.
Inputs: Member ID.
Outputs: MemberProfileResponse with a ParliamentMember record, attendance records, biography details, and PMB sponsorship records.
Entities / values: ParliamentMember, MemberID, MemberBiography, PMBSponsorship.
Ports: backend Go: `MemberRepository`.
Primary adapters: members Lambda (GET /api/v1/members/{id}), SQLite query adapter, S3 manifest/index downloader.
Current implementation:
  backend/members/main.go
  backend/members/internal/usecase/members.go
  backend/members/internal/adapter/sqlite/repository.go
  backend/members/internal/adapter/s3/manifest_loader.go
  backend/members/internal/adapter/s3/index_downloader.go
```

> **Boundary note:** `GetMemberProfile` returns domain values only. Nullable SQL columns are converted inside the SQLite adapter and do not leak into the use case or domain types.

---

### LoadMPBiography

```
Actor: User (iOS app, Members tab -> MP profile)
Goal: Display an MP's Parliament.ca biography details and link sponsored private member's bills to the Bills tracker.
Inputs: Member ID.
Outputs: MemberBiography with service periods, previous roles, education, professional background, sponsored bills, and official Parliament.ca profile URL.
Entities / values: ParliamentMember, MemberID, MemberBiography, ParliamentaryServicePeriod, ParliamentaryRole, SponsoredBillReference.
Ports: iOS Swift: `MPBiographyRepository`.
Primary adapters: BackendMPBiographyRepository (GET /api/v1/members/{id}), MemberBiographySection, MemberBiographyCard, BillsView filtered by sponsored bill numbers.
Current implementation:
  ios/epac/Application/LoadMPBiography.swift
  ios/epac/Domain/MPBiography.swift
  ios/epac/Domain/Ports/MPBiographyRepository.swift
  ios/epac/Data/Repositories/BackendMPBiographyRepository.swift
  ios/epac/Views/Members/MemberProfileView.swift
  ios/epac/Views/Bills/BillsView.swift
```

> **Boundary note:** `LoadMPBiography` consumes the backend JSON contract only. Parliament.ca HTML/XML parsing remains in backend ingestion adapters; iOS does not know the scraping source shape.

---

### ListSittings

```
Actor: User (iOS app, Calendar / Hansard entry points) / Backend API caller
Goal: Browse House sitting dates and their source metadata.
Inputs: Page, per-page, optional from_date and to_date filters.
Outputs: SittingsResponse with Sitting records.
Entities / values: Sitting.
Ports: iOS Swift: `SittingRepository`. Backend Go: no named sitting repository port; current handlers read published artifacts directly through the shared artifact store.
Primary adapters: sittings Lambda (GET /api/v1/sittings), sittings-publisher S3 artifact job, S3 sittings/v1 artifacts, iOS HansardSittingRepositoryAdapter over SwiftDataHansardRepository / Fetch (ourcommons.ca sitting calendar parsing).
Current implementation:
  ios/epac/Domain/Ports/SittingRepository.swift
  ios/epac/Data/Adapters/HansardSittingRepositoryAdapter.swift
  ios/epac/Application/BrowseHansardSitting.swift
  ios/epac/Views/Calendar/SittingCalendarViewModel.swift
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
Ports: iOS Swift: `SittingRepository`. Backend Go: no named sitting repository port; current handlers read published artifacts directly through the shared artifact store.
Primary adapters: sittings Lambda (GET /api/v1/sittings/{date}/speeches), sittings-publisher S3 by-date artifacts, iOS HansardSittingRepositoryAdapter over SwiftDataHansardRepository / Fetch (ourcommons.ca Hansard XML parsing).
Current implementation:
  ios/epac/Domain/Ports/SittingRepository.swift
  ios/epac/Data/Adapters/HansardSittingRepositoryAdapter.swift
  ios/epac/Application/ReadHansardSpeech.swift
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
Ports: iOS Swift: `BillRepository`. Backend Go: `BillRepository`.
Primary adapters: bills Lambda (GET /api/v1/bills), SQLite query adapter, S3 manifest/index downloader, bills-publisher/indexer artifact job, S3 bills/v1 artifacts, iOS LEGISinfoBillRepository wrapping BillsService (LEGISinfo JSON).
Current implementation:
  ios/epac/Domain/Ports/BillRepository.swift
  ios/epac/Data/Adapters/LEGISinfoBillRepository.swift
  ios/epac/Data/Adapters/BillsService.swift
  ios/epac/Views/Bills/BillsView.swift
  ios/epac/Views/Search/SearchView.swift
  backend/bills/main.go
  backend/bills/internal/usecase/bills.go
  backend/bills/internal/adapter/sqlite/repository.go
  backend/bills/internal/adapter/s3/manifest_loader.go
  backend/bills/internal/adapter/s3/index_downloader.go
  backend/bills-publisher/main.go
```

> **Adapter note:** EPAC-2260 moves the backend API path from `bills/v1/all.json` to the manifest-selected SQLite artifact in S3. The backend list use case depends on `BillRepository`; AWS, local `/tmp` files, and `database/sql` stay in adapters.

---

### TrackRoyalAssent

```
Actor: User (iOS app, Home feed / Bills tab)
Goal: Surface current-session bills that recently became law through Royal Assent.
Inputs: Current date, current-session bill records.
Outputs: Bills with Royal Assent in the last 30 days, sorted most recent first.
Entities / values: Bill.
Ports: iOS Swift: `RecentLawQueryPort`, `BillRepository`, `Clock`.
Primary adapters: HomeFeedView RecentlyBecameLawCard, BillsView Became Law filter, LEGISinfoBillRepository wrapping BillsService.
Current implementation:
  ios/epac/Application/TrackRoyalAssent.swift
  ios/epac/Domain/Ports/RecentLawQueryPort.swift
  ios/epac/Domain/Ports/BillRepository.swift
  ios/epac/Data/Adapters/LEGISinfoBillRepository.swift
  ios/epac/Data/Adapters/BillsService.swift
  ios/epac/Views/Home/HomeFeedView.swift
  ios/epac/Views/Bills/BillsView.swift
```

> **Boundary note:** The use case filters typed `Bill` values only. LEGISinfo field names, date parsing, sponsor profile URL construction, and source-link construction remain inside `BillsService`.

---

### NotifyFollowedBillRoyalAssent

```
Actor: iOS background refresh / User foreground bill refresh
Goal: Notify the user when a bill they follow is observed transitioning to Royal Assent.
Inputs: Followed bill state, freshly fetched bill records.
Outputs: Notification content for the followed bill and updated last-known follow state.
Entities / values: Bill, BillFollowState, RoyalAssentNotification.
Ports: iOS Swift: `RoyalAssentNotificationPort`, `BillRepository`.
Primary adapters: BillFollowStore, LiveRoyalAssentNotificationAdapter, BackgroundRefreshManager, BillsView refresh path.
Current implementation:
  ios/epac/Application/NotifyFollowedBillRoyalAssent.swift
  ios/epac/Domain/Entities/RoyalAssentNotification.swift
  ios/epac/Domain/Ports/RoyalAssentNotificationPort.swift
  ios/epac/Data/Adapters/LiveRoyalAssentNotificationAdapter.swift
  ios/epac/Util/BillFollowStore.swift
  ios/epac/Util/BackgroundRefreshManager.swift
  ios/epac/Model/Fetch.swift
```

> **Boundary note:** UserNotifications is adapter detail. The use case formats typed notification content and does not import APNs or `UNUserNotificationCenter`; iOS background wake timing remains governed by BGAppRefresh.

---

### GetBillDepth

```
Actor: User (iOS app, bill detail) / Backend API caller
Goal: Load one bill with relational depth rows such as versions and amendments.
Inputs: Bill ID.
Outputs: BillDepthResponse with Bill metadata, stages, versions, and amendments.
Entities / values: Bill.
Ports: backend Go: `BillRepository`.
Primary adapters: bills Lambda (GET /api/v1/bills/{id}), SQLite query adapter, S3 manifest/index downloader.
Current implementation:
  backend/bills/main.go
  backend/bills/internal/usecase/bills.go
  backend/bills/internal/adapter/sqlite/repository.go
  backend/bills/internal/adapter/s3/manifest_loader.go
  backend/bills/internal/adapter/s3/index_downloader.go
```

> **Boundary note:** `GetBillDepth` returns domain values only. SQLite nulls and optional table/column handling are adapter concerns.

---

### TagPrivateMembersBill

```
Actor: System (Backend Ingest / iOS Service boundary)
Goal: Distinguish and classify bills as Private Members' Bills or Government Bills based on their LEGISinfo document type metadata during ingestion or parsing.
Inputs: LEGISinfo bill type string (`BillTypeEn` or `BillDocumentTypeNameEn`).
Outputs: `Bill.type` value object (`government`, `privateMember`, `senatePublic`, `senatePrivate`).
Entities / values: Bill, BillType.
Ports: backend Go: `Fetcher`; iOS Swift: `BillsService`.
Primary adapters: `backend/bills-indexer/internal/adapter/legisinfo/fetcher.go`, `ios/epac/Data/Adapters/BillsService.swift`.
Current implementation:
  backend/bills-indexer/internal/adapter/legisinfo/fetcher.go
  ios/epac/Data/Adapters/BillsService.swift
```

> **Boundary rule:** The raw LEGISinfo `BillTypeEn` or `BillDocumentTypeNameEn` strings must be mapped to the `BillType` value object at the ingestion/adapter boundary (e.g. `Fetcher` on the backend, `BillsService` on iOS). App use cases and models must only refer to the typed `BillType` value object.

---

### LoadSponsoredPMBs

```
Actor: User (iOS app, Member Profile)
Goal: View the list of Private Members' Bills sponsored by a specific Member of Parliament.
Inputs: ParliamentMember.
Outputs: Sorted list of Private Members' Bills sponsored by the member, ordered by introduction date (newest first).
Entities / values: ParliamentMember, Bill.
Ports: iOS Swift: `BillRepository`.
Primary adapters: SponsoredPMBsSection view, BillsService fetcher.
Current implementation:
  ios/epac/Views/Members/SponsoredPMBsSection.swift
  ios/epac/Data/Adapters/BillsService.swift
```

---

### GetOnThisDay

```
Actor: Backend API caller
Goal: Serve prior-year Parliament moments for the same calendar day while backend teardown work is pending.
Inputs: Reference date, item limit.
Outputs: OnThisDayResponse with ranked OnThisDayItem records.
Entities / values: OnThisDayItem, SpeechMessage.
Ports: backend Go: `HansardRepository`.
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

### LoadLobbyingByTopic

```
Actor: Backend API caller / downstream lobbying dashboards
Goal: Load OCL communication reports and registrations mapped to an epac parliamentary topic.
Inputs: Epac topic slug, page, per-page.
Outputs: LobbyingByTopicResult with source-cited communication and registration rows.
Entities / values: OCLSubjectMatter, EpacTopicSlug, LobbyingByTopicResult.
Ports: LobbyingSubjectsRepository, OCLSubjectsSource.
Primary adapters: lobbying Lambda (GET /api/v1/lobbying/by-topic/{slug}), SQLite lobbying-index repository, ocl_topic_map.json source, S3 artifact loader.
Current implementation:
  backend/lobbying/main.go
  backend/lobbying/internal/usecase/usecase.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
  backend/lobbying/internal/adapter/ocltopicmap/source.go
  backend/lobbying/ocl_topic_map.json
```

> **Boundary rule:** The use case depends on the `OCLSubjectsSource` and `LobbyingSubjectsRepository` ports. The checked-in mapping JSON, SQLite artifact, S3 manifest/download details, and Lambda request/response details stay in adapters.

---

### LoadBillLobbyingContext

```
Actor: Backend API caller / iOS bill detail surface
Goal: Summarize OCL communication reports whose high-confidence subject-matter mappings match a bill's subject tags.
Inputs: LEGISinfo bill ID, window in months.
Outputs: BillLobbyingContext with total communications, counts by organization, counts by subject matter, and top organizations.
Entities / values: Bill, BillLobbyingContext, LobbyingSubjectMatch, OrganizationCommunicationCount, OCLSubjectMatter.
Ports: backend Go: `BillSubjectsRepository`, `BillLobbyingCommunicationsRepository`, `OCLSubjectsSource`, `Clock`; iOS Swift: `BillLobbyingContextRepository`.
Primary adapters: lobbying Lambda (GET /api/v1/bills/{legisinfo_id}/lobbying-context), SQLite lobbying-index repository, ocl_topic_map.json source, S3 artifact loader, iOS BackendBillLobbyingContextRepository, BillLobbyingContextPanel.
Current implementation:
  ios/epac/Application/LoadBillLobbyingContext.swift
  ios/epac/Domain/Entities/BillLobbyingContext.swift
  ios/epac/Domain/Ports/BillLobbyingContextRepository.swift
  ios/epac/Data/Repositories/BackendBillLobbyingContextRepository.swift
  ios/epac/Views/Bills/BillLobbyingContextPanel.swift
  ios/epac/Views/Bills/BillDetailView.swift
  backend/lobbying/bill_lobbying_context_endpoint.go
  backend/lobbying/internal/usecase/bill_lobbying_context.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
  backend/lobbying/internal/adapter/ocltopicmap/source.go
  backend/lobbying/ocl_topic_map.json
```

> **Boundary rule:** The use case filters to high-confidence topic mappings and computes the date window/count aggregation without importing Lambda, SQLite, S3, or JSON mapping details. LEGISinfo bill subject/readings storage stays in the read-side SQLite artifact built by `backend/lobbying-index`.

---

### LoadMinisterLobbyingByPortfolio

```
Actor: Backend API caller / downstream minister-profile clients
Goal: Load OCL communication reports for one cabinet minister grouped by cabinet portfolio period.
Inputs: House of Commons member ID.
Outputs: LobbyingByPortfolio response with portfolio periods, top three organizations per period, communications, and mandate-match flags.
Entities / values: Minister, Portfolio, MinisterTenure, LobbyingByPortfolio, OCLSubjectMatter, EpacTopicSlug.
Ports: MinisterRepository, MinisterLobbyingRepository, MandateLetterRepository, OCLTopicMapper, PortfolioBoundaryGapLogger.
Primary adapters: lobbying Lambda (GET /api/v1/ministers/{member_id}/lobbying-by-portfolio), SQLite lobbying-index repository, pre-baked minister communication tables, ocl_topic_map.json source, structured portfolio-boundary logging.
Current implementation:
  backend/lobbying/main.go
  backend/lobbying/internal/usecase/minister_portfolio.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
  backend/lobbying/internal/adapter/ocltopicmap/source.go
  backend/lobbying-index/internal/adapter/sqlite/minister_prebake.go
```

> **Boundary rule:** The use case owns portfolio-period grouping, mandate-match flagging, top-organization ranking, and tenure fallback policy. SQLite table names, checked-in topic mapping JSON, S3 artifact loading, and API Gateway request details stay in adapters.

---

### LoadCabinetLobbyingOverview

```
Actor: Backend API caller / downstream cabinet dashboards
Goal: Rank cabinet ministers by total OCL communication reports received during a Parliament.
Inputs: Parliament number, optional portfolio filter.
Outputs: CabinetLobbyingSummary rows sorted by communication count, including minister portfolios and top organizations.
Entities / values: Minister, Portfolio, MinisterTenure, CabinetLobbyingSummary.
Ports: MinisterRepository, MinisterLobbyingRepository, PortfolioBoundaryGapLogger.
Primary adapters: lobbying Lambda (GET /api/v1/cabinet/lobbying-overview), SQLite lobbying-index repository, pre-baked minister portfolio and communication tables, structured portfolio-boundary logging.
Current implementation:
  backend/lobbying/main.go
  backend/lobbying/internal/usecase/minister_portfolio.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
  backend/lobbying-index/internal/adapter/sqlite/minister_prebake.go
```

> **Boundary rule:** Ranking and empty-overview behavior live in the use case. HTTP query parsing, artifact loading, and pre-baked minister communication lookups stay in adapters.

---

### LoadMPLobbyingExposure

```
Actor: Backend API caller / iOS MP profile
Goal: Load one MP's precomputed OCL lobbying exposure summary, all-subject distribution, and paged communication timeline.
Inputs: Member ID, parliament number, exposure window (`30d`, `3m`, `12m`, or `all`), timeline page.
Outputs: MPLobbyingExposureResult with summary, subject breakdown, 50-row timeline page, OCL citation, and source URL.
Entities / values: MPLobbyingSummary, LobbyingTimelineEntry, LobbyingSubjectDistribution, MemberID.
Ports: backend Go: `MPLobbyingRepository`, `LobbyingSubjectDistributionQuery`; iOS Swift: `MPLobbyingExposureRepository`.
Primary adapters: lobbying Lambda (GET /api/v1/members/{id}/lobbying-exposure), SQLite lobbying-index repository, `mp_lobbying_*` read-model tables, S3 artifact loader, iOS MPLobbyingService, MPLobbyingTabView.
Current implementation:
  ios/epac/Domain/MPLobbyingExposure.swift
  ios/epac/Util/MPLobbyingService.swift
  ios/epac/Views/Members/MPLobbyingTabView.swift
  backend/lobbying/main.go
  backend/lobbying/application/mp_exposure.go
  backend/lobbying/domain/mp_exposure.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
  backend/lobbying-index/internal/adapter/sqlite/mp_aggregation.go
```

> **Boundary rule:** The use case computes request policy such as allowed windows, 50-row paging, empty responses, citations, and low-confidence bill-link suppression. The serving SQLite adapter owns read-model SQL; quarterly summary refresh and table assembly live in `backend/lobbying-index`.

---

### GetEstimates

```
Actor: Backend API caller
Goal: Read Main Estimates rows by fiscal year or organization.
Inputs: Fiscal year, optional organization id.
Outputs: EstimatesResponse with GC InfoBase-derived Estimate rows.
Entities / values: EstimateOrg.
Ports: backend Go: `EstimatesReader`.
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
Ports: backend Go: no named riding-boundary repository port; current handlers read published artifacts directly through the shared artifact store.
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
Ports: backend Go: no named calendar repository port; current handler reads the published ICS artifact directly through the shared artifact store.
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
Ports: backend Go: no named app-config repository port; current handler reads the published config artifact directly through the shared artifact store.
Primary adapters: config Lambda (GET /api/v1/config), config publisher, S3 config/v1/app.json artifact.
Current implementation:
  backend/config/main.go
  backend/config/cmd/publisher/main.go
```

> **Adapter note:** EPAC-1916 introduces the config artifact as `config/v1/app.json`. Environment-specific config should be isolated by the deployment's artifact bucket or prefix rather than by changing the API response shape.

---

### TrackSenateAppointments

```
Actor: Backend ingestion job / iOS app
Goal: Keep current Senator rows associated with appointment date, appointing prime minister, province, declared affiliation, and Orders in Council source.
Inputs: Senator roster/appointment payload from backend or existing Senate roster adapter.
Outputs: Senator values with optional SenateAppointment facts.
Entities / values: Senator, SenateAppointment.
Ports: iOS Swift: `SenatorAppointmentQueryPort`.
Primary adapters: SenatorsService, HomeFeedSwiftDataRepository, SenatorCard, MyMPView, HomeFeedView.
Current implementation:
  ios/epac/Model/Senator.swift
  ios/epac/Util/SenatorsService.swift
  ios/epac/Data/Repositories/HomeFeedSwiftDataRepository.swift
  ios/epac/Views/Senate/SenatorCard.swift
  ios/epac/Views/MyMP/MyMPView.swift
  ios/epac/Views/Home/HomeFeedView.swift
```

> **Boundary note:** iOS decodes typed appointment fields when the roster payload includes them and does not scrape PCO or Senate HTML. Backend ingestion/parsing remains outside the iOS adapter.

---

### LoadAppointingPM

```
Actor: User (iOS app, Home / My MP)
Goal: See which prime minister appointed each province Senator and when, with their declared affiliation and PCO Orders in Council citation.
Inputs: User's saved MP province.
Outputs: Province-filtered Senator cards with appointment summary and source link.
Entities / values: Senator, SenateAppointment.
Ports: iOS Swift: `SenatorAppointmentQueryPort`.
Primary adapters: LoadHomeFeed, HomeFeedSwiftDataRepository, SenatorCard, MyMPView, HomeFeedView.
Current implementation:
  ios/epac/Domain/UseCases/LoadHomeFeed.swift
  ios/epac/Data/Repositories/HomeFeedSwiftDataRepository.swift
  ios/epac/Views/Senate/SenatorCard.swift
  ios/epac/Views/MyMP/MyMPView.swift
  ios/epac/Views/Home/HomeFeedView.swift
```

> **Notification note:** Senate appointment notification eligibility uses the canonical `senate` topic ID added to `shared/topic-taxonomy/parliamentary_topics.json`; existing topic-follow storage carries that ID through device preferences.

---

### FollowTopic

```
Actor: User (iOS app, Topics tab or notifications prompt)
Goal: Follow a parliamentary topic locally so topic-aware app surfaces can prioritize it.
Inputs: Topic selection.
Outputs: Updated followed-topics list.
Entities / values: ParliamentaryTopic.
Ports: iOS Swift: `TopicPreferenceStore`.
Primary adapters: TopicsView, TopicFollowStoreAdapter wrapping TopicFollowStore. The backend device registration route was retired by EPAC-1921, so there is no active device-registration port.
Current implementation:
  ios/epac/Domain/Ports/TopicPreferenceStore.swift
  ios/epac/Data/Adapters/TopicFollowStoreAdapter.swift
  ios/epac/Application/FollowTopic.swift
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

### DispatchPushNotification

```
Actor: Backend API caller (live-vote-poller Lambda)
Goal: Fan out an internal push notification payload to registered device subscriptions.
Inputs: PushNotificationPayload.
Outputs: DispatchResult with subscription, delivered, and failed-delivery counts.
Entities / values: PushNotificationPayload, LiveVoteNotification, DeviceSubscription, DispatchResult.
Ports: backend Go: `DeviceSubscriptionRepository`, `PushNotificationClient`.
Primary adapters: push-notification-dispatcher Lambda, Postgres/pgx device subscription repository, APNs HTTP client.
Current implementation:
  backend/push-notification-dispatcher/internal/domain/domain.go
  backend/push-notification-dispatcher/internal/usecase/dispatch_push_notification.go
  backend/push-notification-dispatcher/internal/adapter/postgres/subscriptions.go
  backend/push-notification-dispatcher/internal/adapter/apns/client.go
  backend/push-notification-dispatcher/main.go
```

> **Boundary rule:** `DispatchPushNotification` owns fan-out policy and depends
> only on the subscription lookup and push delivery ports. API Gateway events,
> environment variables, `pgx`, APNs endpoint construction, HTTP transport, and
> response mapping stay in `main.go` or `internal/adapter/`.

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
Ports: backend Go: `MemberContentRepository`. iOS Swift: no member-content protocol exists today; the current member vote UI uses view/adapters directly.
Primary adapters: MemberVotingHistoryView, MemberVotingRecordView, member-votes Lambda (GET /api/v1/members/{id}/votes), S3ArtifactMemberContentRepository, member-votes-publisher.
Current implementation:
  ios/epac/Views/Members/MemberVotingHistoryView.swift
  ios/epac/Views/Members/MemberVotingRecordView.swift
  backend/member-votes/main.go
  backend/member-content/content.go
  backend/member-votes-publisher/main.go
```

### LoadMPLobbyingExposure

```
Actor: User (iOS app, Members tab -> MP profile)
Goal: Load and filter an MP's lobbying dashboard payload.
Inputs: MP identifier, page number, page size, date range, subject filter.
Outputs: Paginated lobbying timeline plus precomputed totals, subject breakdown, top organizations, cohort comparison, and selectable subject list.
Entities / values: MPLobbyingSummary, MPLobbyingTimelineEntry, MPLobbyingSubjectDistribution, MPLobbyingTopOrganization, MPLobbyingCohortComparison.
Ports: MPLobbyingRepository, LobbyingSubjectDistributionQuery, CohortStatisticsRepository.
Primary adapters: member-lobbying Lambda (GET /api/v1/members/{id}/lobbying), backend/member-lobbying/usecase, artifact repository.
Current implementation:
  backend/member-lobbying/main.go
  backend/member-lobbying/internal/usecase/usecase.go
  backend/member-lobbying/internal/adapter/artifact/artifact.go
```

### CompareMPLobbyingToCohort

```
Actor: Device (backend API path)
Goal: Compute MP-level lobbying ratios against party and national cohort baselines.
Inputs: MP-level total lobbying volume and cohort baseline values.
Outputs: MPLobbyingCohortComparison.
Entities / values: MPLobbyingCohortComparison.
Ports: CohortStatisticsRepository.
Primary adapters: backend/member-lobbying/internal/usecase/usecase.go
```

---

### LoadMinisterLobbyingByPortfolio (iOS)

```
Actor: User (iOS app, Members tab -> cabinet minister profile)
Goal: Browse OCL communications grouped by the cabinet portfolio period in which they occurred.
Inputs: Member ID.
Outputs: Portfolio-period sections with lobbying communications and mandate-letter match flags.
Entities / values: MemberID, MinisterPortfolioLobbyingPeriod, MinisterLobbyingCommunication.
Ports: CabinetLobbyingRepository.
Primary adapters: MinisterLobbyingTabView, MemberProfileView, BackendCabinetLobbyingRepository, GET /api/v1/ministers/{member_id}/lobbying-by-portfolio.
Current implementation:
  ios/epac/Application/LoadMinisterLobbyingByPortfolio.swift
  ios/epac/Domain/Ports/CabinetLobbyingRepository.swift
  ios/epac/Domain/Entities/CabinetLobbying.swift
  ios/epac/Data/Repositories/BackendCabinetLobbyingRepository.swift
  ios/epac/Views/Members/MinisterLobbyingTabView.swift
  ios/epac/Views/Members/MemberProfileView.swift
```

> **Boundary note:** Portfolio grouping and mandate matching are backend policy outputs; the iOS use case only loads those values and the SwiftUI adapter renders sectioning, highlighting, and OCL citations.

---

### LoadCabinetLobbyingOverview (iOS)

```
Actor: User (iOS app, Accountability tab -> Cabinet Lobbying)
Goal: Compare lobbying exposure across cabinet ministers and portfolios.
Inputs: Parliament number.
Outputs: Ranked ministers, available portfolio filters, and most-active organizations per portfolio.
Entities / values: CabinetLobbyingOverview, CabinetLobbyingMinisterSummary, CabinetLobbyingOrganizationSummary.
Ports: CabinetLobbyingRepository.
Primary adapters: CabinetLobbyingOverviewView, AccountabilityHubView, BackendCabinetLobbyingRepository, GET /api/v1/cabinet/lobbying-overview.
Current implementation:
  ios/epac/Application/LoadCabinetLobbyingOverview.swift
  ios/epac/Domain/Ports/CabinetLobbyingRepository.swift
  ios/epac/Domain/Entities/CabinetLobbying.swift
  ios/epac/Data/Repositories/BackendCabinetLobbyingRepository.swift
  ios/epac/Views/Accountability/CabinetLobbyingOverviewView.swift
  ios/epac/Views/Accountability/AccountabilityHubView.swift
```

> **Boundary note:** Ranking and portfolio aggregate values are loaded as backend response values; SwiftUI owns presentation filtering and navigation from the accountability hub.

---

### FetchLiveParliamentStatus

> Retired in EPAC-1921. The backend `live-status` Lambda and `/api/v1/live` route are removed from desired state. The historical architecture note remains in `docs/architecture/live-status-backend-epac165.md`.

---

### Lobbying-index builder boundary

The lobbying-index build is orchestrated by `infra/lobbying-index.asl.json`.
Production sequencing is owned by the Step Functions state-machine definition,
not by a single sequential `backend/lobbying-index/main.go` Lambda invocation.
The Lambda is a per-phase adapter: `PHASE` selects one phase runner, the router
hydrates the local SQLite working DB from the predecessor phase's S3 intermediate
when one exists, and it persists the updated DB for the next phase.

Intermediate working keys live under `<LOBBYING_INDEX_PREFIX>/tmp/<Phase>.sqlite`;
the published artifact remains `<LOBBYING_INDEX_PREFIX>/index.sqlite` with
`manifest.json`. The working-key namespace must stay distinct from the published
key so an incomplete run is never observed as the serving artifact. Intermediate
downloads verify the object's `content-hash-sha256` metadata against the streamed
SHA-256 before a phase mutates the DB; hash mismatch is a hard phase failure.

---

### IngestOCLData

```
Actor: Step Functions Task state `IngestOCLData`.
Goal: Build raw OCL SQLite tables from authoritative source payloads for downstream lobbying processing.
Inputs: OCL communications ZIP URL, OCL registrations ZIP URL, ourcommons members XML URL, OCL subject-matter HTML URLs.
Outputs: SQLite database path and raw tables:
  ocl_communication_primary,
  ocl_communication_dpohs,
  ocl_communication_subject_matters,
  ocl_registration_primary,
  ocl_registration_subject_matters,
  ocl_registration_in_house_lobbyists,
  ocl_registration_consultant_lobbyists,
  ocl_subject_matter_types,
  members.
Ports: `OCLSource`, `MembersSource`, `SubjectMatterSource`, `RawTableWriter`.
Primary adapters: `PHASE=IngestOCLData` dispatch in backend/lobbying-index/main.go, S3 intermediate persist, ocl.Fetcher, ourcommons.Fetcher, subjects.Fetcher, sqlite.Writer.
Current implementation:
  backend/lobbying-index/main.go
  backend/lobbying-index/internal/adapter/ocl/fetcher.go
  backend/lobbying-index/internal/adapter/ourcommons/fetcher.go
  backend/lobbying-index/internal/adapter/subjects/fetcher.go
  backend/lobbying-index/internal/adapter/sqlite/writer.go
  backend/lobbying-index/internal/adapter/s3/s3.go
```

> **Boundary rule:** The use case owns raw-feed orchestration and row counting.
> Step Functions owns cross-phase sequencing, and the Lambda router owns S3
> intermediate persistence. Feed-specific transport/parsing and SQL schema
> details remain in adapters.

---

### BuildMPLobbyingTables

```
Actor: Step Functions Task state `AggregateMPLobbying`.
Goal: Populate MP lobbying exposure read tables from raw OCL SQLite tables.
Inputs: Build-time SQLite database containing OCL communications, DPOHs, subject matters, and members.
Outputs: `mp_lobbying_timeline_entries`, `mp_lobbying_summaries`, `mp_lobbying_subject_breakdowns`, and `lobbying_cohort_averages` rows.
Entities / values: MPLobbyingSummary, LobbyingTimelineEntry, LobbyingSubjectDistribution, LobbyingCohortAverage.
Ports: backend Go: `MPLobbyingAggregator`.
Primary adapters: `PHASE=BuildMPLobbyingTables` dispatch in backend/lobbying-index/main.go, S3 intermediate hydrate/persist, SQLite aggregation runner.
Current implementation:
  backend/lobbying-index/main.go
  backend/lobbying-index/internal/usecase/mp_aggregation.go
  backend/lobbying-index/internal/adapter/sqlite/mp_aggregation.go
  backend/lobbying-index/internal/adapter/s3/s3.go
```

> Boundary rule: the constructed `NewBuildMPLobbyingTables(...).Execute(...)`
> use case owns the named builder operation and the aggregator port; SQLite DDL,
> SQL dialect differences, JSON aggregation, and window-function details remain
> in the adapter. Step Functions owns when this phase runs, and the Lambda router
> owns S3 working-DB hydrate/persist.

---

### BuildOrganizationTables

```
Actor: Step Functions Task state `BuildOrganizationTables`.
Goal: Aggregate raw OCL tables into derived lobbyist organization and subject-matter tables for the serving Lambda.
Inputs: Populated raw OCL SQLite tables (ocl_registration_primary, ocl_communication_primary, etc.).
Outputs: lobbyist_organizations, lobbyist_communications, lobbyist_registrations, lobbyist_subject_matters.
Ports: `OrgAggregator`.
Primary adapters: `PHASE=BuildOrganizationTables` dispatch in backend/lobbying-index/main.go, S3 intermediate hydrate/persist, sqlite.Aggregator.
Current implementation:
  backend/lobbying-index/main.go
  backend/lobbying-index/internal/usecase/org_aggregation.go
  backend/lobbying-index/internal/adapter/sqlite/aggregator.go
  backend/lobbying-index/internal/adapter/s3/s3.go
```

> **Boundary rule:** Use-case policy invokes the aggregator port only. All SQLite
> CTE logic stays in the adapter. This phase consumes the MP lobbying intermediate;
> the state-machine definition, not `main.go`, owns the cross-phase order.

---

### BuildBillContextTables

```
Actor: Step Functions Task state `BuildBillContextTables`.
Goal: Fetch bill metadata from parl.ca/legisinfo and build bill lobbying context tables for the serving Lambda.
Inputs: parl.ca/legisinfo JSON API, ocl_topic_map.json, parliament/session numbers.
Outputs: legisinfo_bill_subject_tags, legisinfo_bill_readings.
Ports: `LegisInfoSource`, `BillContextWriter`.
Primary adapters: `PHASE=BuildBillContextTables` dispatch in backend/lobbying-index/main.go, S3 intermediate hydrate/persist, legisinfo.Fetcher, sqlite.Aggregator.
Current implementation:
  backend/lobbying-index/main.go
  backend/lobbying-index/internal/usecase/org_aggregation.go
  backend/lobbying-index/internal/adapter/legisinfo/fetcher.go
  backend/lobbying-index/internal/adapter/sqlite/aggregator.go
  backend/lobbying-index/internal/adapter/s3/s3.go
  backend/lobbying-index/ocl_topic_map.json
```

> **Boundary rule:** Use-case policy must not import net/http or parl.ca-specific
> JSON structs — these belong in the legisinfo adapter. The phase consumes the
> organization-table intermediate and writes the bill-context intermediate through
> the Lambda router's S3 adapter.

---

### PreBakeMinisterCommunications

```
Actor: Step Functions Task state `PreBakeMinisterCommunications`.
Goal: Scrape the current Cabinet, resolve each minister to a House member ID, and pre-bake minister lobbying tables in the build-time SQLite artifact.
Inputs: pm.gc.ca Cabinet page, pm.gc.ca mandate-letter page/article, build-time SQLite database containing OCL communications and members, parliament number.
Outputs: `minister_portfolio_periods`, `minister_mandate_topic_mappings`, and `minister_communications`.
Entities / values: Minister, Portfolio, MemberID, EpacTopicSlug.
Ports: `CabinetSource`, `MinisterTableWriter`.
Primary adapters: `PHASE=PreBakeMinisterCommunications` dispatch in backend/lobbying-index/main.go, S3 intermediate hydrate/persist, cabinet.Fetcher, sqlite minister prebake writer.
Current implementation:
  backend/lobbying-index/main.go
  backend/lobbying-index/internal/usecase/minister_prebake.go
  backend/lobbying-index/internal/adapter/cabinet/fetcher.go
  backend/lobbying-index/internal/adapter/sqlite/minister_prebake.go
  backend/lobbying-index/internal/adapter/s3/s3.go
```

> **Boundary rule:** The use case owns the named builder operation and the
> `CabinetSource` / `MinisterTableWriter` ports. pm.gc.ca HTML parsing, keyword
> inference from mandate-letter text, SQLite DDL, and the DPOH fuzzy-name join
> stay in adapters. Final publication is a separate `UploadArtifact` /
> `PHASE=Finalize` state, not part of this use case.

---

### IngestHansard

```
Actor: Scheduler (EventBridge, daily after Parliament publishes)
Goal: Fetch the latest Hansard XML from ourcommons.ca, parse interventions, and write canonical speech records to the database.
Inputs: Target parliament number, session number, sitting date (EventBridge payload).
Outputs: Upserted speech records in speeches table; structured JSON log on stderr.
Entities / values: Hansard, SubjectOfBusiness, SpeechMessage.
Ports: backend Go: `HansardRepository`, `Clock`.
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

### CompareMPLobbyingToCohort

```
Actor: Scheduler (after quarterly OCL ingest) / Backend API caller
Goal: Compare one MP's lobbying communication volume with their party cohort and the national MP average.
Inputs: Parliament number, member ID, current MP membership, per-MP lobbying communication totals.
Outputs: `lobbying_cohort_averages` rows and comparison rows with mp_total, party_avg, national_avg, ratio_vs_party, and ratio_vs_national.
Entities / values: CohortComparison, ParliamentMember, MemberID.
Ports: backend Python: `CohortStatisticsRepository`.
Primary adapters: backend/lobbying/cohort_averages.py, PostgreSQL members table, per-MP lobbying totals table, lobbying_cohort_averages table.
Current implementation:
  backend/lobbying/cohort_averages.py
  backend/migrations/013_lobbying_cohort_averages.sql
```

> Boundary rule: cohort averaging and ratio calculation stay in the use case;
> the Postgres adapter owns table names, SQL, and the optional `psycopg`
> dependency.

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
Ports: backend Go: `ArtifactStore`.
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
Ports: backend Python: no named port artifact; `backend/statistics_artifacts.py` is the shared publishing adapter helper. Backend Go: no `Clock` interface is involved in this Python pipeline.
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
Ports: backend Go: `SubjectsRepository`, `Clock`.
Primary adapters: hansard-subjects-index CLI, PostgreSQL speeches table.
Current implementation:
  backend/hansard-subjects-index/application/usecase.go
  backend/hansard-subjects-index/repository/postgres.go
```

> Boundary rule: artifact publishing, S3, CloudFront, and manifest concerns stay outside the use case; the use case only reads source subjects and emits deterministic JSON.

---

### AggregateLobbyistOrganizations

```
Actor: Scheduler / backend data operator
Goal: Build canonical lobbyist organization aggregates from OCL registration and communication source rows.
Inputs: Current Parliament session window, prior Parliament session window, OCL registration rows, OCL communication rows, seeded organization aliases.
Outputs: Upserted `lobbyist_organizations` rows and pending alias observations for ambiguous name-only matches.
Entities / values: LobbyistOrganization, OrganizationSector, CommunicationCount, ParliamentSession.
Ports: backend Go: `OrganizationDirectoryQuery`, `LobbyistOrganizationRepository`.
Primary adapters: backend/lobbying-index SQLite aggregator, lobbying-index artifact tables.
Current implementation:
  backend/lobbying/application/aggregate.go
  backend/lobbying/application/normalizer.go
  backend/lobbying-index/internal/adapter/sqlite/aggregator.go
```

> Boundary rule: OCL table names and SQLite JSON storage stay in the build-time adapter. The use case sees registration/communication source values and domain aggregates only.

---

### LoadLobbyistOrganizationProfile

```
Actor: Backend caller / User (iOS app)
Goal: Load one canonical lobbyist organization profile by organization ID.
Inputs: Canonical organization ID; iOS may first resolve an organization name through the directory endpoint when an entry point lacks the canonical ID.
Outputs: LobbyistOrganization aggregate with name, type, sector, registration status, registrations, registered lobbyists, active subject matters, recent communications, subject-matter counts, communication trend, and top DPOHs contacted.
Entities / values: LobbyistOrganization, LobbyistRegistration, LobbyistOrganizationCommunication, LobbyistOrganizationSubjectMatter, OrganizationSector, CommunicationCount.
Ports: backend Go: `LobbyistOrganizationRepository`; iOS Swift: `LobbyistOrganizationRepository`.
Primary adapters: backend/lobbying SQLite artifact repository, S3 artifact loader, lobbying Lambda (GET /api/v1/lobbying/organizations/{id}), iOS BackendLobbyistOrganizationRepository, LobbyistOrganizationView.
Current implementation:
  ios/epac/Application/LoadLobbyistOrganizationProfile.swift
  ios/epac/Domain/Entities/LobbyistOrganization.swift
  ios/epac/Domain/Ports/LobbyistOrganizationRepository.swift
  ios/epac/Data/Repositories/BackendLobbyistOrganizationRepository.swift
  ios/epac/Views/Accountability/LobbyistOrganizationView.swift
  backend/lobbying/application/aggregate.go
  backend/lobbying/organizations_endpoint.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
```

> Boundary rule: HTTP request/response types stay in the backend Lambda and iOS REST adapter. SwiftUI imports stay in `LobbyistOrganizationView`; the iOS view-model consumes domain/use-case values.

---

### BrowseLobbyistOrganizations

```
Actor: Backend caller / User (iOS app)
Goal: Browse canonical lobbyist organizations for profile discovery.
Inputs: Search text, sector filter, communication-volume sort direction, limit, offset.
Outputs: Ordered LobbyistOrganization aggregates.
Entities / values: LobbyistOrganization, CommunicationCount.
Ports: backend Go: `LobbyistOrganizationRepository`; iOS Swift: `LobbyistOrganizationRepository`.
Primary adapters: backend/lobbying SQLite artifact repository, S3 artifact loader, lobbying Lambda (GET /api/v1/lobbying/organizations), iOS BackendLobbyistOrganizationRepository, LobbyistOrganizationDirectoryView.
Current implementation:
  ios/epac/Domain/Ports/LobbyistOrganizationRepository.swift
  ios/epac/Data/Repositories/BackendLobbyistOrganizationRepository.swift
  ios/epac/Views/Accountability/LobbyistOrganizationDirectoryView.swift
  backend/lobbying/application/aggregate.go
  backend/lobbying/organizations_endpoint.go
  backend/lobbying/internal/usecase/open_lobbying_index.go
  backend/lobbying/internal/adapter/sqlite/repository.go
  backend/lobbying/internal/adapter/s3/
```

> Boundary rule: pagination/search policy is represented as plain input values; no HTTP adapter types leak inward.

---

### PollLiveDivisions

```
Actor: System (cron scheduler)
Goal: Fetch active parliamentary divisions, identify concluded votes, save them as artifacts, and dispatch a push notification payload.
Inputs: Current time (to verify sitting hours).
Outputs: Concluded division artifacts written to storage, push notifications dispatched.
Entities / values: Division.
Ports: backend Go: `DivisionsFetching`, `ArtifactRepository`, `PushDispatching`, `Clock`.
Primary adapters: backend/live-vote-poller Lambda handler, ourcommons API client, S3/local-disk artifact repository, HTTP push dispatcher client.
Current implementation:
  backend/live-vote-poller/main.go
  backend/live-vote-poller/internal/usecase/poll_live_divisions.go
  backend/live-vote-poller/internal/adapter/ourcommons/divisions_client.go
  backend/live-vote-poller/internal/adapter/artifacts/repository.go
  backend/live-vote-poller/internal/adapter/push/dispatcher.go
```

> Boundary rule: The usecase checks sitting hours and division status independently of how AWS schedules the lambda or how HTTP requests are formed.

---

### LoadPetitionGovernmentResponse

```
Actor: User (iOS app, foreground)
Goal: Surface the government's tabled written response for a petition in the detail view.
Inputs: Petition ID.
Outputs: PetitionGovernmentResponse value object (text, date tabled, responding minister) or nil.
Entities / values: EPetition, PetitionGovernmentResponse.
Ports: iOS Swift: `PetitionGovernmentResponseQueryPort`.
Primary adapters: BackendPetitionGovernmentResponseQueryPort, PetitionDetailView.
Current implementation:
  ios/epac/Domain/Ports/PetitionGovernmentResponseQueryPort.swift
  ios/epac/Domain/UseCases/LoadPetitionGovernmentResponse.swift
  ios/epac/Data/Repositories/BackendPetitionGovernmentResponseQueryPort.swift
  ios/epac/Views/Petitions/PetitionDetailView.swift
```

> Boundary rule: HTML/wire-format parsing of the petitions source lives only in the backend ingestion adapter; iOS consumes a typed JSON shape.

---

### LoadMPAttendance

```
Actor: User (iOS app, foreground)
Goal: Compute an MP's attendance record (attendance rate, breakdown) and compare it against national/party baselines.
Inputs: Member ID.
Outputs: MPAttendance value object containing an AttendanceRecord and optional AttendanceComparison.
Entities / values: ParliamentMember, AttendanceRecord, AttendanceComparison, MPAttendance.
Ports: iOS Swift: `MPAttendanceQueryPort`.
Primary adapters: SwiftDataMPAttendanceAdapter, MemberAttendanceSection, AttendanceRecordCard.
Current implementation:
  ios/epac/Domain/Ports/MPAttendanceQueryPort.swift
  ios/epac/Domain/MPAttendance.swift
  ios/epac/Application/LoadMPAttendance.swift
  ios/epac/Data/Adapters/SwiftDataMPAttendanceAdapter.swift
  ios/epac/Views/Members/MemberAttendanceSection.swift
```

> Boundary rule: The use case and domain types must not import SwiftData, SwiftUI, or UIKit. The adapter handles raw SwiftData tally querying; presentation policy (paired absences are handled distinctly from unexplained ones) lives in the use case.

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
| Nova Scotia | `ios/epac/Data/Adapters/Hansard/NovaScotiaHansardAdapter.swift` | Registered in `JurisdictionRoutedHansardRepository` at app startup. |
| Ontario | `ios/epac/Data/Adapters/Hansard/OntarioHansardAdapter.swift` | Registered in `JurisdictionRoutedHansardRepository` at app startup. |
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
