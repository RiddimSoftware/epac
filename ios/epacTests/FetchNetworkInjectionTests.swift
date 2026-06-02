@testable import epac
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct FetchNetworkInjectionTests {
    @Test func downloadHansardUsesInjectedNetworkService() async throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        let expectedFirstURL = URL(
            string: "https://www.ourcommons.ca/en/parliamentary-business/2026-04-29"
        )!

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FetchInjectionMockURLProtocol.self]
        let injectedSession = URLSession(configuration: configuration)

        FetchInjectionMockURLProtocol.reset()
        FetchInjectionMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        defer { FetchInjectionMockURLProtocol.reset() }

        let injectedNetworkService = NetworkService(
            session: injectedSession,
            cacheStore: try makeIsolatedCacheStore()
        )

        let container = try makeContainer()
        let fetch = Fetch(modelContainer: container, networkService: injectedNetworkService)

        // downloadHansard will throw (the mock returns 404, so HTML parsing fails downstream).
        // What we are asserting here is that the injected URLSession received the request —
        // i.e. that downloadHansard routed through the injected NetworkService rather than
        // through NetworkService.shared.
        _ = try? await fetch.downloadHansard(date)

        let observed = FetchInjectionMockURLProtocol.observedURLs
        #expect(observed.first == expectedFirstURL)
    }

    @Test func defaultInitKeepsSharedNetworkService() throws {
        let container = try makeContainer()
        // Existing call sites must keep compiling and behaving identically without
        // passing a NetworkService — the default parameter is the only thing keeping
        // epacApp.swift and BackgroundRefreshManager.swift unchanged.
        _ = Fetch(modelContainer: container)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(SchemaV10.models), configurations: config)
    }

    private func makeIsolatedCacheStore() throws -> HTTPResponseCacheStore {
        let suiteName = "FetchNetworkInjectionTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FetchNetworkInjectionTests-\(UUID().uuidString)", isDirectory: true)
        return HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
    }
}

private enum FetchInjectionMockURLProtocolError: Error {
    case missingHandler
}

private final class FetchInjectionMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var observedURLsStorage: [URL?] = []
    private static let lock = NSLock()

    static var observedURLs: [URL?] {
        lock.lock()
        defer { lock.unlock() }
        return observedURLsStorage
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        observedURLsStorage = []
        requestHandler = nil
    }

    private static func recordObserved(_ url: URL?) {
        lock.lock()
        defer { lock.unlock() }
        observedURLsStorage.append(url)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw FetchInjectionMockURLProtocolError.missingHandler
            }
            Self.recordObserved(request.url)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
