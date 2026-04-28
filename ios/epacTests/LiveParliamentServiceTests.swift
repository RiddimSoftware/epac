@testable import epac
import Foundation
import Testing

struct LiveParliamentServiceTests {
    @Test func fetchStatusDecodesSittingResponse() async throws {
        let baseURL = URL(string: "https://api.example.test")!
        var capturedRequest: URLRequest?
        let service = LiveParliamentService(baseURL: baseURL) { request in
            capturedRequest = request
            let body = Data("""
            {
              "status": "sitting",
              "is_sitting": true,
              "business_type": "Oral Questions",
              "current_item_title": "Oral Questions",
              "current_bill_number": null,
              "current_speaker_name": "Steven MacKinnon",
              "division_in_progress": false,
              "checked_at": "2026-04-28T14:00:00Z",
              "last_changed_at": "2026-04-28T13:59:30.123Z",
              "source_url": "https://www.ourcommons.ca/en"
            }
            """.utf8)
            return (
                body,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let status = try await service.fetchStatus()

        #expect(capturedRequest?.url?.absoluteString == "https://api.example.test/api/v1/live")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(status.status == .sitting)
        #expect(status.isSitting)
        #expect(status.businessType == "Oral Questions")
        #expect(status.currentSpeakerName == "Steven MacKinnon")
        #expect(status.lastChangedAt != nil)
    }

    @Test func fetchStatusThrowsForServerError() async {
        let service = LiveParliamentService(baseURL: URL(string: "https://api.example.test")!) { request in
            (
                Data(),
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            )
        }

        await #expect(throws: URLError.self) {
            _ = try await service.fetchStatus()
        }
    }
}
