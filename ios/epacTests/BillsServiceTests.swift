@testable import epac
import Foundation
import Testing

/// Mapping tests for `BillsService`, the LEGISinfo → `Bill` boundary.
///
/// The bill-depth backend (versions, diff, committee, amendments, lobbying,
/// PBO) is keyed by the numeric LEGISinfo id, not the display bill number, so
/// `Bill.id` must carry that numeric id while `Bill.number` stays the display
/// value. Regression coverage for EPAC-2307.
@Suite(.serialized)
struct BillsServiceTests {
    @Test func billMappingUsesNumericLegisInfoIdAsBillId() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        defer { BillsServiceMockURLProtocol.requestHandler = nil }

        BillsServiceMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.legisInfoJSON()
            )
        }

        let bills = try await BillsService.fetchBills(parliament: 45, session: 1, network: harness.service)
        let bill = try #require(bills.first { $0.number == "C-11" })

        // Backend bill-depth key — must be the numeric LEGISinfo id, not "C-11".
        #expect(bill.id == "13608745")
        #expect(bill.number == "C-11")
    }

    @Test func billMappingFallsBackToNumberWhenLegisInfoIdMissingOrZero() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        defer { BillsServiceMockURLProtocol.requestHandler = nil }

        BillsServiceMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.legisInfoJSON()
            )
        }

        let bills = try await BillsService.fetchBills(parliament: 45, session: 1, network: harness.service)

        // BillId absent entirely → fall back to the display number.
        let missing = try #require(bills.first { $0.number == "S-12" })
        #expect(missing.id == "S-12")

        // BillId present but not a usable id (<= 0) → fall back to the number.
        let zero = try #require(bills.first { $0.number == "C-99" })
        #expect(zero.id == "C-99")
    }

    // MARK: - Fixtures

    /// Minimal LEGISinfo JSON array exercising the three id cases the mapping
    /// must handle: a numeric id, an absent id, and a non-usable (<= 0) id.
    private static func legisInfoJSON() -> Data {
        Data(
            """
            [
              {
                "BillId": 13608745,
                "BillNumberFormatted": "C-11",
                "ShortTitleEn": "An Act respecting example data",
                "ParliamentNumber": 45,
                "SessionNumber": 1
              },
              {
                "BillNumberFormatted": "S-12",
                "ShortTitleEn": "An Act respecting senate example data",
                "ParliamentNumber": 45,
                "SessionNumber": 1
              },
              {
                "BillId": 0,
                "BillNumberFormatted": "C-99",
                "ShortTitleEn": "An Act respecting zero-id example data",
                "ParliamentNumber": 45,
                "SessionNumber": 1
              }
            ]
            """.utf8
        )
    }

    private func makeHarness() throws -> BillsServiceNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillsServiceMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BillsServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillsServiceTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return BillsServiceNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }
}

private struct BillsServiceNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum BillsServiceMockURLProtocolError: Error {
    case missingHandler
}

private final class BillsServiceMockURLProtocol: URLProtocol {
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
                throw BillsServiceMockURLProtocolError.missingHandler
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
