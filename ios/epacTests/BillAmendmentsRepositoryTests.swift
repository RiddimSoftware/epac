@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BillAmendmentsRepositoryTests {
    @Test func billAmendmentsDecodesBackendResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedRequest: URLRequest?

        BillAmendmentsMockURLProtocol.requestHandler = { request in
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
        defer { BillAmendmentsMockURLProtocol.requestHandler = nil }

        let repository = BackendBillAmendmentsRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let loadedAmendments = try await repository.loadBillAmendments(billID: "C-8")
        let amendments = try #require(loadedAmendments)
        let request = try #require(capturedRequest)
        let requestURL = try #require(request.url)

        #expect(requestURL.path == "/api/v1/bills/C-8")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(amendments.count == 3)

        let first = try #require(amendments.first)
        #expect(first.id == "C-8-a-1")
        #expect(first.number == "LIB-1")
        #expect(first.title == "Clause 5 — replace subsection")
        #expect(first.sponsorName == "Hon. Member A")
        #expect(first.stage == "Committee")
        #expect(first.status == .passed)
        #expect(first.statusLabel == "adopted")
        #expect(first.proposedOn == expectedUTCDate(year: 2026, month: 6, day: 4))
        #expect(first.text.contains("Bill C-8, in Clause 5"))
        #expect(first.sourceURL?.absoluteString == "https://www.parl.ca/legisinfo/amendment/1")

        let second = try #require(amendments.dropFirst().first)
        #expect(second.status == .defeated)
        #expect(second.statusLabel == "negatived")

        let third = try #require(amendments.dropFirst(2).first)
        #expect(third.status == .withdrawn)
        #expect(third.statusLabel == "withdrawn")
        #expect(third.title == nil)
    }

    @Test func billAmendmentsReturnsEmptyArrayWhenBillHasNoAmendments() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillAmendmentsMockURLProtocol.requestHandler = { request in
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
        defer { BillAmendmentsMockURLProtocol.requestHandler = nil }

        let repository = BackendBillAmendmentsRepository(network: harness.service, baseURL: baseURL)
        let amendments = try await repository.loadBillAmendments(billID: "C-9")

        #expect(amendments == [])
    }

    @Test func billAmendmentsReturnsNilOnNoContent() async throws {
        let setup = try makeRepository(statusCode: 204)
        defer { setup.harness.cleanup() }
        defer { BillAmendmentsMockURLProtocol.requestHandler = nil }

        let amendments = try await setup.repository.loadBillAmendments(billID: "C-10")

        #expect(amendments == nil)
    }

    @Test func billAmendmentsReturnsNilOnNotFound() async throws {
        let setup = try makeRepository(statusCode: 404)
        defer { setup.harness.cleanup() }
        defer { BillAmendmentsMockURLProtocol.requestHandler = nil }

        let amendments = try await setup.repository.loadBillAmendments(billID: "C-11")

        #expect(amendments == nil)
    }

    @Test func billAmendmentsThrowsOnServerError() async throws {
        let setup = try makeRepository(statusCode: 500)
        defer { setup.harness.cleanup() }
        defer { BillAmendmentsMockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            _ = try await setup.repository.loadBillAmendments(billID: "C-12")
        }
    }

    private func makeRepository(
        statusCode: Int
    ) throws -> (repository: BackendBillAmendmentsRepository, harness: BillAmendmentsNetworkHarness) {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillAmendmentsMockURLProtocol.requestHandler = { request in
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
            repository: BackendBillAmendmentsRepository(
                network: harness.service,
                baseURL: baseURL
            ),
            harness: harness
        )
    }

    private func makeHarness() throws -> BillAmendmentsNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillAmendmentsMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BillAmendmentsRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillAmendmentsRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return BillAmendmentsNetworkHarness(
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
                "amendments": [
                  {
                    "id": "C-8-a-1",
                    "number": "LIB-1",
                    "title": "Clause 5 — replace subsection",
                    "status": "adopted",
                    "stage": "Committee",
                    "sponsor_name": "Hon. Member A",
                    "proposed_on": "2026-06-04",
                    "text": "That Bill C-8, in Clause 5, be amended by replacing line 10 on page 3 with the following: ...",
                    "source_url": "https://www.parl.ca/legisinfo/amendment/1"
                  },
                  {
                    "id": "C-8-a-2",
                    "number": "CPC-2",
                    "title": "Clause 7 — delete",
                    "status": "negatived",
                    "stage": "Committee",
                    "sponsor_name": "Hon. Member B",
                    "proposed_on": "2026-06-05",
                    "text": "That Bill C-8, Clause 7, be deleted."
                  },
                  {
                    "id": "C-8-a-3",
                    "number": "NDP-3",
                    "status": "withdrawn",
                    "stage": "Report Stage",
                    "sponsor_name": "Hon. Member C",
                    "proposed_on": "2026-06-08",
                    "text": "That Bill C-8 be amended at Report Stage by ..."
                  }
                ]
              }
            }
            """.utf8
        )
    }
}

private struct BillAmendmentsNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum BillAmendmentsMockURLProtocolError: Error {
    case missingHandler
}

private final class BillAmendmentsMockURLProtocol: URLProtocol {
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
                throw BillAmendmentsMockURLProtocolError.missingHandler
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
