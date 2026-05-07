@testable import epac
import Foundation
import Testing

// Tests for the Universal Link URL parsing logic.
//
// These cover the path-segment extraction that ContentView.handleUniversalLink
// and ContentViewModel.onOpenURL rely on — the logic that decides which tab to
// switch to and what query to pre-fill from an incoming URL.
struct DeepLinkRoutingTests {

    // MARK: - Path segment extraction

    @Test func memberURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/member/12345")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "member")
        #expect(segments.dropFirst().first == "12345")
        #expect(Int(segments.dropFirst().first ?? "") == 12345)
    }

    @Test func billURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/bill/C-50")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "bill")
        #expect(segments.dropFirst().first == "C-50")
    }

    @Test func voteURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/vote/45-1/123")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "vote")
        let voteRef = segments.dropFirst().joined(separator: "/")
        #expect(voteRef == "45-1/123")
    }

    @Test func sittingURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/sitting/2024-04-29")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "sitting")
        #expect(segments.dropFirst().first == "2024-04-29")
    }

    @Test func eventURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/event/2026-05-25")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "event")
        #expect(segments.dropFirst().first == "2026-05-25")
    }

    @Test func topicURLSlugConversion() {
        let url = URL(string: "https://epac.riddimsoftware.com/topic/housing-affordability")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "topic")
        let slug = segments.dropFirst().first ?? ""
        let query = slug.replacingOccurrences(of: "-", with: " ")
        #expect(query == "housing affordability")
    }

    @Test func setupURLSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/setup/postal-code")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "setup")
    }

    @Test func homeURLHasNoPathSegments() {
        let url = URL(string: "https://epac.riddimsoftware.com/")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.isEmpty)
        #expect(segments.first == nil)
    }

    @Test func legacyAppURLPreservesQueryItems() {
        let url = URL(string: "https://epac.riddimsoftware.com/app?date=2024-04-29T00:00:00Z&subjectID=HAN123")!
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments.first == "app")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "date" })?.value == "2024-04-29T00:00:00Z")
        #expect(items?.first(where: { $0.name == "subjectID" })?.value == "HAN123")
    }

    // MARK: - Sitting date parsing (ContentViewModel.onOpenURL path branch)

    @Test func sittingDateParsing() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let date = try #require(formatter.date(from: "2024-04-29"))
        let roundTripped = formatter.string(from: date)
        #expect(roundTripped == "2024-04-29")
    }

    @Test func sittingDateParsingRejectsMalformed() {
        // DateFormatter on Darwin is lenient about separator characters, so we
        // guard with a regex before parsing — exactly as ContentViewModel does.
        let iso8601Pattern = /^\d{4}-\d{2}-\d{2}$/
        func parseSittingDate(_ s: String) -> Date? {
            guard s.wholeMatch(of: iso8601Pattern) != nil else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: s)
        }

        #expect(parseSittingDate("not-a-date") == nil)
        #expect(parseSittingDate("2024/04/29") == nil)
        #expect(parseSittingDate("2024-04-29") != nil)
    }
}
