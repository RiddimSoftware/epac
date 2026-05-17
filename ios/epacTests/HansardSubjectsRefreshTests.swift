@testable import epac
import Foundation
import Testing

// MARK: - Mocks

final class MockArtifactFetcher: ArtifactFetching, @unchecked Sendable {
    var fetchCallCount = 0
    var lastPath: String?
    var lastETag: String?
    var stubbedResult: ArtifactFetchResult?
    var stubbedError: Error?

    func fetch(path: String, eTag: String?) async throws -> ArtifactFetchResult? {
        fetchCallCount += 1
        lastPath = path
        lastETag = eTag
        if let error = stubbedError { throw error }
        return stubbedResult
    }
}

final class MockHansardSubjectsIngestor: HansardSubjectsIngesting, @unchecked Sendable {
    var ingestCallCount = 0
    var lastIngested: [HansardSubjectEntry]?
    var stubbedError: Error?

    func ingestHansardSubjects(_ subjects: [HansardSubjectEntry]) async throws {
        ingestCallCount += 1
        lastIngested = subjects
        if let error = stubbedError { throw error }
    }
}

// MARK: - Helpers

private func makeDefaults() -> UserDefaults {
    let name = "HansardSubjectsRefreshTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func samplePayload(subjects: [HansardSubjectEntry] = [
    HansardSubjectEntry(hansardID: "h1", title: "Housing"),
    HansardSubjectEntry(hansardID: "h2", title: "Budget")
]) -> Data {
    // swiftlint:disable:next force_try
    try! JSONEncoder().encode(subjects)
}

// MARK: - Unit Tests

@MainActor
struct HansardSubjectsRefreshTests {

    // Cold launch: no prior timestamp → fetch runs and ingestor is called.
    @Test func coldLaunchTriggersRefresh() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = ArtifactFetchResult(data: samplePayload(), eTag: "v1")
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults, now: { Date() }
        )

        await sut.refreshIfNeeded()

        #expect(fetcher.fetchCallCount == 1)
        #expect(ingestor.ingestCallCount == 1)
        #expect(ingestor.lastIngested?.count == 2)
    }

    // Warm cache: last refresh < 1 hour ago → refreshIfNeeded is a no-op.
    @Test func warmCacheSkipsRefreshWithinOneHour() async throws {
        let fetcher = MockArtifactFetcher()
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(-1800), forKey: "epac.sync.hansardSubjects")
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults, now: { Date() }
        )

        await sut.refreshIfNeeded()

        #expect(fetcher.fetchCallCount == 0)
        #expect(ingestor.ingestCallCount == 0)
    }

    // Throttle guard: last refresh < 5 minutes ago → refresh() itself skips the network call.
    @Test func throttleGuardBlocksRefreshWithinFiveMinutes() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = ArtifactFetchResult(data: samplePayload(), eTag: nil)
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(-120), forKey: "epac.sync.hansardSubjects")
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults, now: { Date() }
        )

        // refresh() bypasses the 1-hour check but still applies the 5-minute guard.
        await sut.refresh()

        #expect(fetcher.fetchCallCount == 0)
    }

    // Ingest failure: timestamp and ETag must remain unchanged; existing state preserved.
    @Test func ingestFailurePreservesState() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = ArtifactFetchResult(data: samplePayload(), eTag: "new-etag")
        let ingestor = MockHansardSubjectsIngestor()
        ingestor.stubbedError = URLError(.cannotDecodeContentData)
        let defaults = makeDefaults()
        let previousTimestamp = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(previousTimestamp, forKey: "epac.sync.hansardSubjects")
        defaults.set("old-etag", forKey: "epac.sync.hansardSubjects.eTag")
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_010_000) }
        )

        await sut.refresh()

        let storedTimestamp = defaults.object(forKey: "epac.sync.hansardSubjects") as? Date
        #expect(storedTimestamp == previousTimestamp)
        #expect(defaults.string(forKey: "epac.sync.hansardSubjects.eTag") == "old-etag")
    }

    // ETag hit (304): ingestor not called, but timestamp is updated to throttle next call.
    @Test func eTagMatchSkipsIngestAndUpdatesTimestamp() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = nil // nil → 304 Not Modified
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults, now: { fixedNow }
        )

        await sut.refresh()

        #expect(fetcher.fetchCallCount == 1)
        #expect(ingestor.ingestCallCount == 0)
        let stored = defaults.object(forKey: "epac.sync.hansardSubjects") as? Date
        #expect(stored == fixedNow)
    }

    // Network failure: ingestor not called; no state mutation.
    @Test func networkFailureDoesNotCorruptState() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedError = URLError(.notConnectedToInternet)
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults, now: { Date() }
        )

        await sut.refresh()

        #expect(ingestor.ingestCallCount == 0)
        #expect(defaults.object(forKey: "epac.sync.hansardSubjects") == nil)
    }

    // ETag is persisted after a successful ingest so subsequent calls send it.
    @Test func eTagPersistedAfterSuccessfulIngest() async throws {
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = ArtifactFetchResult(data: samplePayload(), eTag: "etag-xyz")
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults,
            now: { Date() }
        )

        await sut.refresh()

        #expect(defaults.string(forKey: "epac.sync.hansardSubjects.eTag") == "etag-xyz")
    }
}

// MARK: - Integration Tests

@MainActor
struct HansardSubjectsRefreshIntegrationTests {

    // Two consecutive refreshes with same payload → second is a no-op at ingestor boundary.
    @Test func consecutiveRefreshesSecondIsNoOpAtIngestor() async throws {
        let subjects = [HansardSubjectEntry(hansardID: "h1", title: "Climate")]
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(subjects)
        let fetcher = MockArtifactFetcher()
        fetcher.stubbedResult = ArtifactFetchResult(data: data, eTag: "v1")
        let ingestor = MockHansardSubjectsIngestor()
        let defaults = makeDefaults()
        // Advance time by 2 hours on each call so the throttle window is always clear.
        var callIndex = 0
        let sut = HansardSubjectsRefresh(
            fetcher: fetcher, ingestor: ingestor, defaults: defaults,
            now: {
                callIndex += 1
                return Date(timeIntervalSince1970: Double(callIndex) * 7200)
            }
        )

        // First refresh: new data → fetch + ingest.
        await sut.refresh()
        #expect(fetcher.fetchCallCount == 1)
        #expect(ingestor.ingestCallCount == 1)

        // Simulate server returning 304 (same ETag) on the second call.
        fetcher.stubbedResult = nil

        // Second refresh: 304 → ingestor not called.
        await sut.refresh()
        #expect(fetcher.fetchCallCount == 2)
        #expect(ingestor.ingestCallCount == 1)
    }
}
