@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BillVersionDiffRepositoryTests {
    @Test func billVersionDiffDecodesBackendResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedRequest: URLRequest?

        BillVersionDiffMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.billVersionDiffJSON()
            )
        }

        defer { harness.cleanup() }
        defer { BillVersionDiffMockURLProtocol.requestHandler = nil }

        let repository = BackendBillVersionDiffRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let loadedDiff = try await repository.loadBillVersionDiff(
            billID: "C-8",
            fromVersionID: "C-8-v1",
            toVersionID: "C-8-v3"
        )
        let diff = try #require(loadedDiff)
        let request = try #require(capturedRequest)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(requestURL.path == "/api/v1/bills/C-8/diff")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(components.queryItems?.contains(URLQueryItem(name: "from", value: "C-8-v1")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "to", value: "C-8-v3")) == true)

        #expect(diff.fromVersion.id == "C-8-v1")
        #expect(diff.fromVersion.label == "First reading")
        #expect(diff.toVersion.id == "C-8-v3")
        #expect(diff.toVersion.label == "As passed by the House")
        #expect(diff.clauseDiffs.count == 4)

        let added = try #require(diff.clauseDiffs.first { $0.changeType == .added })
        #expect(added.label == "Clause 3")
        #expect(added.fromText.isEmpty)
        #expect(added.toText.contains("The Minister shall"))
        #expect(added.hansardAnchorURL?.absoluteString == "https://example.test/hansard/c-8-clause-3")

        let removed = try #require(diff.clauseDiffs.first { $0.changeType == .removed })
        #expect(removed.label == "Clause 7")
        #expect(removed.fromText.contains("repealed"))
        #expect(removed.toText.isEmpty)

        let modified = try #require(diff.clauseDiffs.first { $0.changeType == .modified })
        #expect(modified.label == "Clause 5")
        #expect(modified.fromText.contains("annually"))
        #expect(modified.toText.contains("quarterly"))

        let unchanged = try #require(diff.clauseDiffs.first { $0.changeType == .unchanged })
        #expect(unchanged.label == "Clause 1")
    }

    @Test func billVersionDiffReturnsNilOnNoContent() async throws {
        let setup = try makeRepository(statusCode: 204)
        defer { setup.harness.cleanup() }
        defer { BillVersionDiffMockURLProtocol.requestHandler = nil }

        let diff = try await setup.repository.loadBillVersionDiff(
            billID: "C-8",
            fromVersionID: "v1",
            toVersionID: "v2"
        )

        #expect(diff == nil)
    }

    @Test func billVersionDiffReturnsNilOnNotFound() async throws {
        let setup = try makeRepository(statusCode: 404)
        defer { setup.harness.cleanup() }
        defer { BillVersionDiffMockURLProtocol.requestHandler = nil }

        let diff = try await setup.repository.loadBillVersionDiff(
            billID: "C-8",
            fromVersionID: "v1",
            toVersionID: "v2"
        )

        #expect(diff == nil)
    }

    @Test func billVersionDiffThrowsOnServerError() async throws {
        let setup = try makeRepository(statusCode: 500)
        defer { setup.harness.cleanup() }
        defer { BillVersionDiffMockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            _ = try await setup.repository.loadBillVersionDiff(
                billID: "C-8",
                fromVersionID: "v1",
                toVersionID: "v2"
            )
        }
    }

    @Test func changeTypeMapsKnownSynonyms() {
        #expect(BillClauseChangeType.from("added") == .added)
        #expect(BillClauseChangeType.from("inserted") == .added)
        #expect(BillClauseChangeType.from("removed") == .removed)
        #expect(BillClauseChangeType.from("deleted") == .removed)
        #expect(BillClauseChangeType.from("modified") == .modified)
        #expect(BillClauseChangeType.from("replaced") == .modified)
        #expect(BillClauseChangeType.from("unchanged") == .unchanged)
        #expect(BillClauseChangeType.from("context") == .unchanged)
        #expect(BillClauseChangeType.from("") == .modified)
        #expect(BillClauseChangeType.from("garbage") == .modified)
    }

    private func makeRepository(
        statusCode: Int
    ) throws -> (repository: BackendBillVersionDiffRepository, harness: BillVersionDiffNetworkHarness) {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillVersionDiffMockURLProtocol.requestHandler = { request in
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
            repository: BackendBillVersionDiffRepository(
                network: harness.service,
                baseURL: baseURL
            ),
            harness: harness
        )
    }

    private func makeHarness() throws -> BillVersionDiffNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillVersionDiffMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BillVersionDiffRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillVersionDiffRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return BillVersionDiffNetworkHarness(
            service: NetworkService(session: session, cacheStore: cacheStore),
            userDefaultsSuiteName: suiteName,
            cacheDirectory: cacheDirectory
        )
    }

    private static func billVersionDiffJSON() -> Data {
        Data(
            """
            {
              "from": {
                "id": "C-8-v1",
                "label": "First reading",
                "stage": "First Reading",
                "chamber": "House of Commons",
                "published_on": "2026-04-27"
              },
              "to": {
                "id": "C-8-v3",
                "label": "As passed by the House",
                "stage": "Third Reading",
                "chamber": "House of Commons",
                "published_on": "2026-06-04"
              },
              "clauses": [
                {
                  "id": "clause-1",
                  "label": "Clause 1",
                  "change_type": "unchanged",
                  "from_text": "Short title.",
                  "to_text": "Short title."
                },
                {
                  "id": "clause-3",
                  "label": "Clause 3",
                  "change_type": "added",
                  "from_text": "",
                  "to_text": "The Minister shall publish quarterly progress reports to Parliament.",
                  "hansard_anchor_url": "https://example.test/hansard/c-8-clause-3"
                },
                {
                  "id": "clause-5",
                  "label": "Clause 5",
                  "change_type": "modified",
                  "from_text": "The Minister shall report annually on the program.",
                  "to_text": "The Minister shall report quarterly on the program."
                },
                {
                  "id": "clause-7",
                  "label": "Clause 7",
                  "change_type": "removed",
                  "from_text": "Section 12 of the Act is repealed.",
                  "to_text": ""
                }
              ]
            }
            """.utf8
        )
    }
}

private struct BillVersionDiffNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum BillVersionDiffMockURLProtocolError: Error {
    case missingHandler
}

private final class BillVersionDiffMockURLProtocol: URLProtocol {
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
                throw BillVersionDiffMockURLProtocolError.missingHandler
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
