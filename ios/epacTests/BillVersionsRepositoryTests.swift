@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BillVersionsRepositoryTests {
    @Test func billVersionsDecodesBackendResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedRequest: URLRequest?

        BillVersionsMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.billDepthJSON()
            )
        }

        defer { harness.cleanup() }
        defer { BillVersionsMockURLProtocol.requestHandler = nil }

        let repository = BackendBillVersionsRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let loadedVersions = try await repository.loadBillVersions(billID: "C-8")
        let versions = try #require(loadedVersions)
        let request = try #require(capturedRequest)
        let requestURL = try #require(request.url)

        #expect(requestURL.path == "/api/v1/bills/C-8")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(versions.count == 3)

        let first = try #require(versions.first)
        #expect(first.id == "C-8-v1")
        #expect(first.label == "First reading")
        #expect(first.stage == "First Reading")
        #expect(first.chamber == "House of Commons")
        #expect(first.publishedOn == expectedUTCDate(year: 2026, month: 4, day: 27))
        #expect(first.sourceURL?.absoluteString == "https://www.parl.ca/legisinfo/bill/C-8/v1")

        let last = try #require(versions.last)
        #expect(last.id == "C-8-v3")
        #expect(last.label == "As passed by the House")
        #expect(last.title == nil)
        #expect(last.publishedOn == expectedUTCDate(year: 2026, month: 6, day: 4))
    }

    @Test func billVersionsReturnsEmptyArrayWhenBillHasNoVersions() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillVersionsMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"bill": {"id": "C-9", "number": "C-9", "title": "Test"}}"#.utf8)
            )
        }

        defer { harness.cleanup() }
        defer { BillVersionsMockURLProtocol.requestHandler = nil }

        let repository = BackendBillVersionsRepository(network: harness.service, baseURL: baseURL)
        let versions = try await repository.loadBillVersions(billID: "C-9")

        #expect(versions == [])
    }

    @Test func billVersionsReturnsNilOnNoContent() async throws {
        let setup = try makeRepository(statusCode: 204)
        defer { setup.harness.cleanup() }
        defer { BillVersionsMockURLProtocol.requestHandler = nil }

        let versions = try await setup.repository.loadBillVersions(billID: "C-10")

        #expect(versions == nil)
    }

    @Test func billVersionsReturnsNilOnNotFound() async throws {
        let setup = try makeRepository(statusCode: 404)
        defer { setup.harness.cleanup() }
        defer { BillVersionsMockURLProtocol.requestHandler = nil }

        let versions = try await setup.repository.loadBillVersions(billID: "C-11")

        #expect(versions == nil)
    }

    @Test func billVersionsThrowsOnServerError() async throws {
        let setup = try makeRepository(statusCode: 500)
        defer { setup.harness.cleanup() }
        defer { BillVersionsMockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            _ = try await setup.repository.loadBillVersions(billID: "C-12")
        }
    }

    private func makeRepository(
        statusCode: Int
    ) throws -> (repository: BackendBillVersionsRepository, harness: BillVersionsNetworkHarness) {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillVersionsMockURLProtocol.requestHandler = { request in
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
            repository: BackendBillVersionsRepository(
                network: harness.service,
                baseURL: baseURL
            ),
            harness: harness
        )
    }

    private func makeHarness() throws -> BillVersionsNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillVersionsMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BillVersionsRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillVersionsRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return BillVersionsNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private func expectedUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private static func billDepthJSON() -> Data {
        Data(
            """
            {
              "bill": {
                "id": "C-8-45-1",
                "number": "C-8",
                "title": "An Act respecting example data",
                "versions": [
                  {
                    "id": "C-8-v1",
                    "label": "First reading",
                    "title": "First reading text",
                    "stage": "First Reading",
                    "chamber": "House of Commons",
                    "published_on": "2026-04-27",
                    "source_url": "https://www.parl.ca/legisinfo/bill/C-8/v1"
                  },
                  {
                    "id": "C-8-v2",
                    "label": "As reported by committee",
                    "stage": "Committee Report",
                    "chamber": "House of Commons",
                    "published_on": "2026-05-20",
                    "source_url": "https://www.parl.ca/legisinfo/bill/C-8/v2"
                  },
                  {
                    "id": "C-8-v3",
                    "label": "As passed by the House",
                    "stage": "Third Reading",
                    "chamber": "House of Commons",
                    "published_on": "2026-06-04",
                    "source_url": "https://www.parl.ca/legisinfo/bill/C-8/v3"
                  }
                ]
              }
            }
            """.utf8
        )
    }
}

private struct BillVersionsNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum BillVersionsMockURLProtocolError: Error {
    case missingHandler
}

private final class BillVersionsMockURLProtocol: URLProtocol {
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
                throw BillVersionsMockURLProtocolError.missingHandler
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
