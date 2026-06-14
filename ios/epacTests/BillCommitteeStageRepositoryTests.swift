@testable import epac
import Foundation
import Testing

@Suite(.serialized)
struct BillCommitteeStageRepositoryTests {
    @Test func billCommitteeStageDecodesBackendResponse() async throws {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()
        var capturedRequest: URLRequest?

        BillCommitteeStageMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.billCommitteeStageJSON()
            )
        }

        defer { harness.cleanup() }
        defer { BillCommitteeStageMockURLProtocol.requestHandler = nil }

        let repository = BackendBillCommitteeStageRepository(
            network: harness.service,
            baseURL: baseURL
        )

        let loadedStage = try await repository.loadBillCommitteeStage(billID: "C-8")
        let stage = try #require(loadedStage)
        let request = try #require(capturedRequest)
        let requestURL = try #require(request.url)

        #expect(requestURL.path == "/api/v1/bills/C-8/committee-stage")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(stage.committee.id == "FINA")
        #expect(stage.committee.name == "Standing Committee on Finance")
        #expect(stage.committee.chamberCode == "HOC")
        #expect(stage.committee.committeeURL.absoluteString == "https://www.ourcommons.ca/Committees/en/FINA")
        #expect(stage.studiedSince == expectedUTCDate(year: 2026, month: 6, day: 3))
        #expect(stage.studyCompletedAt == expectedUTCDate(year: 2026, month: 6, day: 12))
        #expect(stage.upcomingMeetings.count == 1)
        let upcomingMeeting = try #require(stage.upcomingMeetings.first)
        #expect(upcomingMeeting.id == "FINA-45-1-42")
        #expect(upcomingMeeting.meetingNumber == 42)
        #expect(upcomingMeeting.date == expectedUTCDate(year: 2026, month: 6, day: 18))
        #expect(upcomingMeeting.witnessCount == 0)
        #expect(upcomingMeeting.evidenceURL == nil)
        #expect(stage.pastMeetings.count == 2)
        let firstPastMeeting = try #require(stage.pastMeetings.first)
        let secondPastMeeting = try #require(stage.pastMeetings.dropFirst().first)
        #expect(firstPastMeeting.meetingNumber == 41)
        #expect(firstPastMeeting.witnessCount == 7)
        #expect(firstPastMeeting.evidenceURL?.absoluteString == "https://www.ourcommons.ca/DocumentViewer/en/45-1/FINA/meeting-41/evidence")
        #expect(secondPastMeeting.meetingNumber == 40)
        #expect(secondPastMeeting.witnessCount == nil)
    }

    @Test func billCommitteeStageReturnsNilOnNoContent() async throws {
        let setup = try makeRepository(statusCode: 204)
        defer { setup.harness.cleanup() }
        defer { BillCommitteeStageMockURLProtocol.requestHandler = nil }

        let stage = try await setup.repository.loadBillCommitteeStage(billID: "C-9")

        #expect(stage == nil)
    }

    @Test func billCommitteeStageReturnsNilOnNotFound() async throws {
        let setup = try makeRepository(statusCode: 404)
        defer { setup.harness.cleanup() }
        defer { BillCommitteeStageMockURLProtocol.requestHandler = nil }

        let stage = try await setup.repository.loadBillCommitteeStage(billID: "C-9")

        #expect(stage == nil)
    }

    @Test func billCommitteeStageThrowsOnServerError() async throws {
        let setup = try makeRepository(statusCode: 500)
        defer { setup.harness.cleanup() }
        defer { BillCommitteeStageMockURLProtocol.requestHandler = nil }

        await #expect(throws: URLError.self) {
            _ = try await setup.repository.loadBillCommitteeStage(billID: "C-9")
        }
    }

    private func makeRepository(
        statusCode: Int
    ) throws -> (repository: BackendBillCommitteeStageRepository, harness: BillCommitteeStageNetworkHarness) {
        let baseURL = URL(string: "https://example.test")!
        let harness = try makeHarness()

        BillCommitteeStageMockURLProtocol.requestHandler = { request in
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
            repository: BackendBillCommitteeStageRepository(
                network: harness.service,
                baseURL: baseURL
            ),
            harness: harness
        )
    }

    private func makeHarness() throws -> BillCommitteeStageNetworkHarness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillCommitteeStageMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let suiteName = "BillCommitteeStageRepositoryTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillCommitteeStageRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let cacheStore = HTTPResponseCacheStore(userDefaults: userDefaults, cacheDirectory: cacheDirectory)

        return BillCommitteeStageNetworkHarness(
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

    private static func billCommitteeStageJSON() -> Data {
        Data(
            """
            {
              "committee": {
                "code": "FINA",
                "name": "Standing Committee on Finance",
                "chamber": "HOC",
                "url": "https://www.ourcommons.ca/Committees/en/FINA"
              },
              "studied_since": "2026-06-03",
              "study_completed_at": "2026-06-12",
              "upcoming_meetings": [
                {
                  "id": "FINA-45-1-42",
                  "meeting_number": 42,
                  "date": "2026-06-18",
                  "witness_count": 0,
                  "evidence_url": null
                }
              ],
              "past_meetings": [
                {
                  "id": "FINA-45-1-41",
                  "meeting_number": 41,
                  "date": "2026-06-11",
                  "witness_count": 7,
                  "evidence_url": "https://www.ourcommons.ca/DocumentViewer/en/45-1/FINA/meeting-41/evidence"
                },
                {
                  "id": "FINA-45-1-40",
                  "meeting_number": 40,
                  "date": "2026-06-09"
                }
              ]
            }
            """.utf8
        )
    }
}

private struct BillCommitteeStageNetworkHarness {
    let service: NetworkService
    let userDefaultsSuiteName: String
    let cacheDirectory: URL

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

private enum BillCommitteeStageMockURLProtocolError: Error {
    case missingHandler
}

private final class BillCommitteeStageMockURLProtocol: URLProtocol {
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
                throw BillCommitteeStageMockURLProtocolError.missingHandler
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
