@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct ArtifactServiceTests {
    private let baseURL = URL(string: "https://artifacts.example.test")!
    private let artifactKey = ArtifactKey("members/v1/all.json")

    @Test func coldFetchDownloadsDecodesAndCachesArtifact() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#)
            ],
            artifactResponses: [
                .result(statusCode: 200, data: artifactData("fresh"), etag: #""artifact-v1""#)
            ]
        )
        let harness = makeHarness(network: network)
        defer { harness.cleanup() }

        let decoded = try await harness.service.fetch(artifactKey, as: TestArtifact.self)

        #expect(decoded == TestArtifact(value: "fresh"))
        #expect(await network.manifestRequests.count == 1)
        let artifactRequests = await network.artifactRequests
        #expect(artifactRequests.count == 1)
        #expect(artifactRequests[0].ifNoneMatch == nil)
        #expect(artifactRequests[0].url == artifactKey.url(relativeTo: baseURL))
    }

    @Test func warmCacheReturnsCachedArtifactOnNotModified() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#),
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v2""#), etag: #""manifest-v2""#)
            ],
            artifactResponses: [
                .result(statusCode: 200, data: artifactData("cached"), etag: #""artifact-v1""#),
                .result(statusCode: 304, data: Data(), etag: #""artifact-v1""#)
            ]
        )
        let harness = makeHarness(network: network, manifestTTL: 0)
        defer { harness.cleanup() }

        let first = try await harness.service.fetch(artifactKey, as: TestArtifact.self)
        let second = try await harness.service.fetch(artifactKey, as: TestArtifact.self)

        #expect(first == TestArtifact(value: "cached"))
        #expect(second == TestArtifact(value: "cached"))
        let artifactRequests = await network.artifactRequests
        #expect(artifactRequests.map(\.ifNoneMatch) == [nil, #""artifact-v1""#])
    }

    @Test func manifestETagMatchReturnsCachedArtifactWithoutNetworkCall() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#),
                .result(statusCode: 200, data: manifestData(etag: "artifact-v1"), etag: #""manifest-v2""#)
            ],
            artifactResponses: [
                .result(statusCode: 200, data: artifactData("cached"), etag: #""artifact-v1""#)
            ]
        )
        let harness = makeHarness(network: network, manifestTTL: 0)
        defer { harness.cleanup() }

        _ = try await harness.service.fetch(artifactKey, as: TestArtifact.self)
        let cached = try await harness.service.fetch(artifactKey, as: TestArtifact.self)

        #expect(cached == TestArtifact(value: "cached"))
        #expect(await network.artifactRequests.count == 1)
        #expect(await network.manifestRequests.count == 2)
    }

    @Test func networkFailureReturnsStaleCacheAndPublishesWarning() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#),
                .offline
            ],
            artifactResponses: [
                .result(statusCode: 200, data: artifactData("cached"), etag: #""artifact-v1""#)
            ]
        )
        let harness = makeHarness(network: network, manifestTTL: 0)
        defer { harness.cleanup() }

        _ = try await harness.service.fetch(artifactKey, as: TestArtifact.self)
        let fallback = try await harness.service.fetch(artifactKey, as: TestArtifact.self)

        #expect(fallback == TestArtifact(value: "cached"))
        #expect(harness.warnings.latestWarning == .staleCacheFallback(artifactKey))
    }

    @Test func networkFailureWithoutCacheThrowsTypedOfflineError() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#)
            ],
            artifactResponses: [.offline]
        )
        let harness = makeHarness(network: network)
        defer { harness.cleanup() }

        do {
            _ = try await harness.service.fetch(artifactKey, as: TestArtifact.self)
            Issue.record("Expected offlineAndNoCache")
        } catch ArtifactError.offlineAndNoCache(let key) {
            #expect(key == artifactKey)
        } catch {
            Issue.record("Expected offlineAndNoCache, got \(error)")
        }
    }

    @Test func fetchManifestUsesInMemoryCacheWithinTTL() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#)
            ],
            artifactResponses: []
        )
        let harness = makeHarness(network: network, manifestTTL: 300)
        defer { harness.cleanup() }

        let first = try await harness.service.fetchManifest()
        let second = try await harness.service.fetchManifest()

        #expect(first == second)
        #expect(await network.manifestRequests.count == 1)
    }

    @Test func decodeFailureIsHardFailure() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(statusCode: 200, data: manifestData(etag: #""artifact-v1""#), etag: #""manifest-v1""#)
            ],
            artifactResponses: [
                .result(statusCode: 200, data: Data(#"{"unexpected":true}"#.utf8), etag: #""artifact-v1""#)
            ]
        )
        let harness = makeHarness(network: network)
        defer { harness.cleanup() }

        do {
            _ = try await harness.service.fetch(artifactKey, as: TestArtifact.self)
            Issue.record("Expected decodeFailed")
        } catch ArtifactError.decodeFailed(let key, _) {
            #expect(key == artifactKey)
        } catch {
            Issue.record("Expected decodeFailed, got \(error)")
        }
    }

    @Test func malformedManifestThrowsTypedError() async throws {
        let network = MockArtifactNetwork(
            manifestResponses: [
                .result(
                    statusCode: 200,
                    data: Data(#"{"schema_version":99,"generated_at":"2026-05-17T12:00:00Z","artifacts":[]}"#.utf8),
                    etag: #""manifest-v1""#
                )
            ],
            artifactResponses: []
        )
        let harness = makeHarness(network: network)
        defer { harness.cleanup() }

        do {
            _ = try await harness.service.fetchManifest()
            Issue.record("Expected malformedManifest")
        } catch ArtifactError.malformedManifest {
            return
        } catch {
            Issue.record("Expected malformedManifest, got \(error)")
        }
    }

    private func makeHarness(
        network: MockArtifactNetwork,
        manifestTTL: TimeInterval = 300
    ) -> ArtifactServiceHarness {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactServiceTests-\(UUID().uuidString)", isDirectory: true)
        let warnings = ArtifactServiceWarnings()
        let service = ArtifactService(
            baseURL: baseURL,
            artifactNetwork: network,
            manifestNetwork: network,
            cacheStore: FileManagerArtifactStore(cacheDirectory: cacheDirectory),
            warnings: warnings,
            manifestTTL: manifestTTL,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )
        return ArtifactServiceHarness(service: service, warnings: warnings, cacheDirectory: cacheDirectory)
    }

    private func manifestData(etag: String) -> Data {
        let escapedETag = etag
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return Data(
            """
            {
              "schema_version": 1,
              "generated_at": "2026-05-17T12:00:00Z",
              "artifacts": [
                {
                  "key": "\(artifactKey.rawValue)",
                  "size_bytes": 17,
                  "content_hash_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                  "etag": "\(escapedETag)",
                  "last_modified": "2026-05-17T11:30:00Z",
                  "schema_version": 1
                }
              ]
            }
            """.utf8
        )
    }

    private func artifactData(_ value: String) -> Data {
        Data(#"{"value":"\#(value)"}"#.utf8)
    }
}

private struct ArtifactServiceHarness {
    let service: ArtifactService
    let warnings: ArtifactServiceWarnings
    let cacheDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private struct TestArtifact: Decodable, Equatable {
    let value: String
}

private struct MockArtifactRequest: Equatable, Sendable {
    let url: URL
    let ifNoneMatch: String?
}

private enum MockArtifactResponse: Sendable {
    case result(statusCode: Int, data: Data, etag: String?)
    case offline
}

private actor MockArtifactNetwork: ArtifactHTTPFetching, ManifestFetching {
    private(set) var artifactRequests: [MockArtifactRequest] = []
    private(set) var manifestRequests: [MockArtifactRequest] = []
    private var artifactResponses: [MockArtifactResponse]
    private var manifestResponses: [MockArtifactResponse]

    init(manifestResponses: [MockArtifactResponse], artifactResponses: [MockArtifactResponse]) {
        self.manifestResponses = manifestResponses
        self.artifactResponses = artifactResponses
    }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult {
        artifactRequests.append(MockArtifactRequest(url: url, ifNoneMatch: ifNoneMatch))
        return try nextResult(from: &artifactResponses)
    }

    func fetchManifest(from url: URL, ifNoneMatch: String?) async throws -> ArtifactHTTPResult {
        manifestRequests.append(MockArtifactRequest(url: url, ifNoneMatch: ifNoneMatch))
        return try nextResult(from: &manifestResponses)
    }

    private func nextResult(from responses: inout [MockArtifactResponse]) throws -> ArtifactHTTPResult {
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch responses.removeFirst() {
        case .result(let statusCode, let data, let etag):
            return ArtifactHTTPResult(statusCode: statusCode, data: data, etag: etag)
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }
}
