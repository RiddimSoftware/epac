@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct PBOCostingRepositoryTests {
    @Test func decodesCanonicalByBillResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedRequest: URLRequest?

        PBOCostingMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.canonicalJSON()
            )
        }

        defer { harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        let repository = BackendPBOCostingRepository(network: harness.service, baseURL: baseURL)

        let loaded = try await repository.loadPBOCostings(billID: "C-8")
        let costings = try #require(loaded)
        let request = try #require(capturedRequest)
        let requestURL = try #require(request.url)

        #expect(requestURL.path == "/pbo/by-bill/C-8")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(costings.count == 2)

        let latest = try #require(costings.first)
        #expect(latest.id == "PBO-2026-014")
        #expect(latest.title == "Cost Estimate — Bill C-8")
        #expect(latest.headlineFigureMillions == "1,240")
        #expect(latest.methodologyCategory == "legislative-cost")
        #expect(latest.publishedAt == expectedUTCDate(year: 2026, month: 5, day: 20))
        #expect(latest.reportURL.absoluteString == "https://www.pbo-dpb.ca/reports/pbo-2026-014.pdf")
        #expect(latest.summaryText == "The PBO estimates the five-year cost at $1,240 million.")

        let earlier = try #require(costings.dropFirst().first)
        #expect(earlier.id == "PBO-2025-300")
        #expect(earlier.summaryText == nil)
        #expect(earlier.headlineFigureMillions == "1,100")
    }

    @Test func decodesBareTopLevelArray() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        PBOCostingMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"[{"id":"PBO-9","report_url":"https://www.pbo-dpb.ca/reports/pbo-9.pdf"}]"#.utf8)
            )
        }

        defer { harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        let repository = BackendPBOCostingRepository(network: harness.service, baseURL: baseURL)
        let costings = try #require(try await repository.loadPBOCostings(billID: "C-9"))

        #expect(costings.count == 1)
        #expect(costings.first?.id == "PBO-9")
        #expect(costings.first?.methodologyCategory == "other")
    }

    @Test func fallsBackToSourceURLAndDropsNotesWithNoURL() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        PBOCostingMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    """
                    {
                      "costings": [
                        {"id": "PBO-source-only", "source_url": "https://www.pbo-dpb.ca/reports/source-only"},
                        {"id": "PBO-no-url", "title": "No link"}
                      ]
                    }
                    """.utf8
                )
            )
        }

        defer { harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        let repository = BackendPBOCostingRepository(network: harness.service, baseURL: baseURL)
        let costings = try #require(try await repository.loadPBOCostings(billID: "C-10"))

        // The URL-less note is dropped; the source-only note uses source_url as its report link.
        #expect(costings.count == 1)
        let note = try #require(costings.first)
        #expect(note.id == "PBO-source-only")
        #expect(note.reportURL.absoluteString == "https://www.pbo-dpb.ca/reports/source-only")
    }

    @Test func returnsNilOnNoContent() async throws {
        let setup = try makeRepository(statusCode: 204)
        defer { setup.harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        let costings = try await setup.repository.loadPBOCostings(billID: "C-11")
        #expect(costings == nil)
    }

    @Test func returnsNilOnNotFound() async throws {
        let setup = try makeRepository(statusCode: 404)
        defer { setup.harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        let costings = try await setup.repository.loadPBOCostings(billID: "C-12")
        #expect(costings == nil)
    }

    @Test func throwsOnServerError() async throws {
        let setup = try makeRepository(statusCode: 500)
        defer { setup.harness.cleanup() }
        defer { PBOCostingMockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            _ = try await setup.repository.loadPBOCostings(billID: "C-13")
        }
    }

    private func makeRepository(
        statusCode: Int
    ) throws -> (repository: BackendPBOCostingRepository, harness: PBOCostingNetworkHarness) {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        PBOCostingMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        return (
            repository: BackendPBOCostingRepository(network: harness.service, baseURL: baseURL),
            harness: harness
        )
    }

    private func makeHarness() throws -> PBOCostingNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PBOCostingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "PBOCostingRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PBOCostingRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return PBOCostingNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private func expectedUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(
            from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private static func canonicalJSON() -> Data {
        Data(
            """
            {
              "costings": [
                {
                  "id": "PBO-2026-014",
                  "title": "Cost Estimate — Bill C-8",
                  "headline_figure_millions": "1,240",
                  "methodology_category": "legislative-cost",
                  "published_at": "2026-05-20",
                  "report_url": "https://www.pbo-dpb.ca/reports/pbo-2026-014.pdf",
                  "source_url": "https://www.pbo-dpb.ca/reports/pbo-2026-014",
                  "summary_text": "The PBO estimates the five-year cost at $1,240 million."
                },
                {
                  "id": "PBO-2025-300",
                  "title": "Earlier estimate — Bill C-8",
                  "headline_figure_millions": "1,100",
                  "methodology_category": "legislative-cost",
                  "published_at": "2025-12-01",
                  "report_url": "https://www.pbo-dpb.ca/reports/pbo-2025-300.pdf"
                }
              ]
            }
            """.utf8
        )
    }
}

private struct PBOCostingNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum PBOCostingMockURLProtocolError: Error {
    case missingHandler
}

private final class PBOCostingMockURLProtocol: URLProtocol {
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
                throw PBOCostingMockURLProtocolError.missingHandler
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
