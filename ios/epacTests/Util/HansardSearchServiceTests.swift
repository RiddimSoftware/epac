@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct HansardSearchServiceTests {
    @Test func dateDecoderParsesStandardUTCDate() throws {
        let response = try decodeResponse(sittingDate: "2026-04-27")

        #expect(response.results.first?.sittingDate == expectedUTCDate(year: 2026, month: 4, day: 27))
    }

    @Test func dateDecoderParsesLeapDayInUTC() throws {
        // The issue text lists 2026-02-29, but 2026 is not a leap year.
        let response = try decodeResponse(sittingDate: "2024-02-29")

        #expect(response.results.first?.sittingDate == expectedUTCDate(year: 2024, month: 2, day: 29))
    }

    @Test func dateDecoderParsesNewYearsDayInUTC() throws {
        let response = try decodeResponse(sittingDate: "2026-01-01")

        #expect(response.results.first?.sittingDate == expectedUTCDate(year: 2026, month: 1, day: 1))
    }

    @Test func backendServiceBuildsEncodedQueryItems() async throws {
        let baseURL = URL(string: "https://example.test/staging")!
        let harness = try makeHarness()
        let fixtureData = fixtureJSON()
        var capturedURL: URL?

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                fixtureData
            )
        }

        defer { harness.cleanup() }
        defer { MockURLProtocol.requestHandler = nil }

        let service = BackendHansardSearchService(
            network: harness.network,
            baseURL: baseURL
        )

        _ = try await service.search(
            query: "climate change & jobs",
            speaker: "Jane Doe",
            topic: "cost of living",
            page: 2,
            perPage: 15
        )

        let url = try #require(capturedURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.path == "/staging/api/v1/hansard/search")
        #expect(components.queryItems?.first(where: { $0.name == "query" })?.value == "climate change & jobs")
        #expect(components.queryItems?.first(where: { $0.name == "speaker" })?.value == "Jane Doe")
        #expect(components.queryItems?.first(where: { $0.name == "topic" })?.value == "cost of living")
        #expect(components.queryItems?.first(where: { $0.name == "page" })?.value == "2")
        #expect(components.queryItems?.first(where: { $0.name == "per_page" })?.value == "15")
        #expect(components.percentEncodedQuery?.contains("query=climate%20change%20%26%20jobs") == true)
        #expect(components.percentEncodedQuery?.contains("speaker=Jane%20Doe") == true)
        #expect(components.percentEncodedQuery?.contains("topic=cost%20of%20living") == true)
    }

    @Test func decoderRoundTripsFixtureJSON() throws {
        let response = try BackendHansardSearchService.makeDecoder().decode(
            HansardSearchResponse.self,
            from: fixtureJSON()
        )

        #expect(response.page == 1)
        #expect(response.perPage == 20)
        #expect(response.total == 1)
        #expect(response.results.count == 1)
        #expect(response.results.first?.parliamentNumber == 45)
        #expect(response.results.first?.sessionNumber == 1)
        #expect(response.results.first?.interventionID == "int-123")
        #expect(response.results.first?.messageID == "msg-456")
        #expect(response.results.first?.id == "msg-456")
        #expect(response.results.first?.speakerName == "Jane Example")
        #expect(response.results.first?.partyAbbreviation == "LIB")
        #expect(response.results.first?.ridingName == "Example Centre")
        #expect(response.results.first?.topic == "Housing")
        #expect(response.results.first?.snippet == "A <mark>housing</mark> update.")
        #expect(response.results.first?.score == 0.98)
        #expect(response.results.first?.sittingDate == expectedUTCDate(year: 2026, month: 4, day: 27))
    }

    private func decodeResponse(sittingDate: String) throws -> HansardSearchResponse {
        try BackendHansardSearchService.makeDecoder().decode(
            HansardSearchResponse.self,
            from: fixtureJSON(sittingDate: sittingDate)
        )
    }

    private func expectedUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }

        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }

    private func makeHarness() throws -> NetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "HansardSearchServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HansardSearchServiceTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)
        let network = NetworkService(session: session, cacheStore: cacheStore)

        return NetworkHarness(
            network: network,
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private func fixtureJSON(sittingDate: String = "2026-04-27") -> Data {
        Data(
            """
            {
              "page": 1,
              "per_page": 20,
              "total": 1,
              "results": [
                {
                  "parliament_number": 45,
                  "session_number": 1,
                  "sitting_date": "\(sittingDate)",
                  "intervention_id": "int-123",
                  "message_id": "msg-456",
                  "speaker_name": "Jane Example",
                  "party_abbreviation": "LIB",
                  "riding_name": "Example Centre",
                  "topic": "Housing",
                  "snippet": "A <mark>housing</mark> update.",
                  "score": 0.98
                }
              ]
            }
            """.utf8
        )
    }
}

private struct NetworkHarness {
    let network: NetworkService
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
