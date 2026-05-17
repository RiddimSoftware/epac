// HansardSubjectsRefresh.swift
// epac
//
// Lifecycle glue for background pre-warming of the Hansard subjects search corpus.
// Fetches the compact index artifact, ingests it into SwiftData via the ingestor
// port, and throttles to avoid redundant network round-trips.

import Foundation

// MARK: - Ports (concrete implementations provided by sibling issues)

/// Fetches a remote artifact with ETag-based conditional requests.
/// Returns `nil` when the server responds 304 Not Modified (content unchanged).
protocol ArtifactFetching: Sendable {
    func fetch(path: String, eTag: String?) async throws -> ArtifactFetchResult?
}

struct ArtifactFetchResult: Sendable {
    let data: Data
    let eTag: String?
}

/// Persists decoded Hansard subjects into the local SwiftData store.
/// Implemented by `ArtifactIngestActor` (sibling issue).
protocol HansardSubjectsIngesting: Sendable {
    func ingestHansardSubjects(_ subjects: [HansardSubjectEntry]) async throws
}

// MARK: - DTO

struct HansardSubjectEntry: Codable, Sendable, Equatable {
    let hansardID: String
    let title: String
}

// MARK: - Use-case protocol

protocol HansardSubjectsRefreshing {
    /// Skips refresh if last success was within the 1-hour throttle window.
    func refreshIfNeeded() async
    /// Runs a refresh pass bypassing the 1-hour check; still applies the 5-minute guard.
    func refresh() async
}

// MARK: - Default implementation

@MainActor
final class HansardSubjectsRefresh: HansardSubjectsRefreshing {
    static let shared = HansardSubjectsRefresh()

    private static let artifactPath = "hansard-subjects/v1/all.json"
    private static let lastRefreshKey = "epac.sync.hansardSubjects"
    private static let eTagKey = "epac.sync.hansardSubjects.eTag"
    /// Foreground-transition throttle: skip `refreshIfNeeded` if last refresh < 1 hour ago.
    private static let hourInterval: TimeInterval = 3600
    /// Hard guard: skip even the network round-trip if last refresh < 5 minutes ago.
    private static let fiveMinuteInterval: TimeInterval = 300

    private let fetcher: any ArtifactFetching
    private let ingestor: any HansardSubjectsIngesting
    private let defaults: UserDefaults
    private let now: () -> Date

    init(
        fetcher: any ArtifactFetching = URLSessionArtifactFetcher(),
        ingestor: any HansardSubjectsIngesting = NoopHansardSubjectsIngestor(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.ingestor = ingestor
        self.defaults = defaults
        self.now = now
    }

    func refreshIfNeeded() async {
        let last = defaults.object(forKey: Self.lastRefreshKey) as? Date
        if let last, now().timeIntervalSince(last) < Self.hourInterval {
            Log.debug("HansardSubjectsRefresh: skipped — within 1-hour window")
            return
        }
        await doRefresh()
    }

    func refresh() async {
        await doRefresh()
    }

    private func doRefresh() async {
        let last = defaults.object(forKey: Self.lastRefreshKey) as? Date
        if let last, now().timeIntervalSince(last) < Self.fiveMinuteInterval {
            Log.debug("HansardSubjectsRefresh: skipped — within 5-minute guard")
            return
        }

        let eTag = defaults.string(forKey: Self.eTagKey)

        do {
            guard let result = try await fetcher.fetch(path: Self.artifactPath, eTag: eTag) else {
                // 304 Not Modified — corpus unchanged; still record success to throttle next call.
                defaults.set(now(), forKey: Self.lastRefreshKey)
                Log.debug("HansardSubjectsRefresh: artifact unchanged (ETag hit)")
                return
            }

            let subjects = try JSONDecoder().decode([HansardSubjectEntry].self, from: result.data)
            try await ingestor.ingestHansardSubjects(subjects)

            defaults.set(now(), forKey: Self.lastRefreshKey)
            if let responseETag = result.eTag {
                defaults.set(responseETag, forKey: Self.eTagKey)
            }
            Log.info("HansardSubjectsRefresh: ingested \(subjects.count) subjects")
        } catch {
            // Refresh is opportunistic: preserve existing SwiftData state on any failure.
            Log.error("HansardSubjectsRefresh failed: \(error)")
        }
    }
}

// MARK: - URLSession adapter (placeholder until ArtifactService ships)

struct URLSessionArtifactFetcher: ArtifactFetching {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = BackendConfig.shared.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetch(path: String, eTag: String?) async throws -> ArtifactFetchResult? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        if let eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            return ArtifactFetchResult(data: data, eTag: http.value(forHTTPHeaderField: "ETag"))
        case 304:
            return nil
        default:
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Stub ingestor (placeholder until ArtifactIngestActor ships)

struct NoopHansardSubjectsIngestor: HansardSubjectsIngesting {
    func ingestHansardSubjects(_ subjects: [HansardSubjectEntry]) async throws {
        Log.warning("HansardSubjectsRefresh: ArtifactIngestActor not wired — \(subjects.count) subjects not persisted")
    }
}
