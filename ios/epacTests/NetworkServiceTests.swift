import Foundation
import Testing
@testable import epac

@Suite(.serialized)
struct NetworkServiceTests {
    @Test func getStoresETagAndReturnsCachedDataOnNotModified() async throws {
        let url = URL(string: "https://example.test/parliament/members")!
        let firstBody = Data(#"{"members":[1]}"#.utf8)
        let secondBody = Data("unexpected".utf8)
        let harness = try makeHarness()
        var seenValidators: [String?] = []
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            seenValidators.append(request.value(forHTTPHeaderField: "If-None-Match"))

            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["ETag": #""members-v1""#]
                    )!,
                    firstBody
                )
            }

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: ["ETag": #""members-v1""#]
                )!,
                secondBody
            )
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        let (storedData, storedResponse) = try await harness.service.data(from: url)
        let (cachedData, cachedResponse) = try await harness.service.data(from: url)

        #expect(storedData == firstBody)
        #expect((storedResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(cachedData == firstBody)
        #expect((cachedResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(seenValidators == [nil, #""members-v1""#])
    }

    @Test func getUsesLastModifiedWhenETagIsUnavailable() async throws {
        let url = URL(string: "https://example.test/parliament/calendar")!
        let body = Data("<calendar />".utf8)
        let lastModified = "Tue, 28 Apr 2026 14:00:00 GMT"
        let harness = try makeHarness()
        var seenLastModified: [String?] = []
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            seenLastModified.append(request.value(forHTTPHeaderField: "If-Modified-Since"))

            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Last-Modified": lastModified]
                    )!,
                    body
                )
            }

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": lastModified]
                )!,
                Data()
            )
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        let (storedData, _) = try await harness.service.data(from: url)
        let (cachedData, cachedResponse) = try await harness.service.data(from: url)

        #expect(storedData == body)
        #expect(cachedData == body)
        #expect((cachedResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(seenLastModified == [nil, lastModified])
    }

    @Test func postRequestsDoNotAttachValidatorsOrStoreResponses() async throws {
        let url = URL(string: "https://example.test/topic/follow")!
        let harness = try makeHarness()
        var seenValidators: [(etag: String?, lastModified: String?)] = []
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            seenValidators.append((
                request.value(forHTTPHeaderField: "If-None-Match"),
                request.value(forHTTPHeaderField: "If-Modified-Since")
            ))

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": #""post-\#(requestCount)""#]
                )!,
                Data("body-\(requestCount)".utf8)
            )
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (firstData, _) = try await harness.service.data(for: request)
        let (secondData, _) = try await harness.service.data(for: request)

        #expect(firstData == Data("body-1".utf8))
        #expect(secondData == Data("body-2".utf8))
        #expect(seenValidators.count == 2)
        #expect(seenValidators.allSatisfy { $0.etag == nil && $0.lastModified == nil })
    }

    @Test func getDoesNotSendValidatorWhenCachedBodyIsMissing() async throws {
        let url = URL(string: "https://example.test/parliament/votes")!
        let initialBody = Data("votes-v1".utf8)
        let refreshedBody = Data("votes-v2".utf8)
        let harness = try makeHarness()
        var seenValidators: [String?] = []
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            seenValidators.append(request.value(forHTTPHeaderField: "If-None-Match"))

            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["ETag": #""votes-v1""#]
                    )!,
                    initialBody
                )
            }

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": #""votes-v2""#]
                )!,
                refreshedBody
            )
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        let (storedData, _) = try await harness.service.data(from: url)
        try FileManager.default.removeItem(at: harness.cacheDirectory)
        let (refreshedData, refreshedResponse) = try await harness.service.data(from: url)

        #expect(storedData == initialBody)
        #expect(refreshedData == refreshedBody)
        #expect((refreshedResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(seenValidators == [nil, nil])
    }

    @Test func getClearsStaleCacheWhenResponseCannotBeRevalidated() async throws {
        let url = URL(string: "https://example.test/parliament/bills")!
        let harness = try makeHarness()
        var seenValidators: [String?] = []
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            seenValidators.append(request.value(forHTTPHeaderField: "If-None-Match"))

            switch requestCount {
            case 1:
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["ETag": #""bills-v1""#]
                    )!,
                    Data("bills-v1".utf8)
                )
            case 2:
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Cache-Control": "no-store"]
                    )!,
                    Data("bills-private".utf8)
                )
            default:
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["ETag": #""bills-v2""#]
                    )!,
                    Data("bills-v2".utf8)
                )
            }
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        let (firstData, _) = try await harness.service.data(from: url)
        let (noStoreData, _) = try await harness.service.data(from: url)
        let (freshData, _) = try await harness.service.data(from: url)

        #expect(firstData == Data("bills-v1".utf8))
        #expect(noStoreData == Data("bills-private".utf8))
        #expect(freshData == Data("bills-v2".utf8))
        #expect(seenValidators == [nil, #""bills-v1""#, nil])
    }

    private func makeHarness() throws -> NetworkServiceHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "NetworkServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkServiceTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        let service = NetworkService(session: session, cacheStore: cacheStore)

        return NetworkServiceHarness(
            service: service,
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }
}

private struct NetworkServiceHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum MockURLProtocolError: Error {
    case missingHandler
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw MockURLProtocolError.missingHandler
            }

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
