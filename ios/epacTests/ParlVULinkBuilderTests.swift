@testable import epac
import Foundation
import Testing

struct ParlVULinkBuilderTests {

    @Test func csvDateParserReturnsDateForCalendarClassToken() {
        let date = DateUtils.parseCSVDateString("2026-01-27")

        #expect(date != nil)
    }

    @Test func csvDateParserRejectsNonDateCalendarClassToken() {
        let date = DateUtils.parseCSVDateString("chamber-meeting")

        #expect(date == nil)
    }

    @Test func houseDebateURLUsesParlVUPowerBrowserPattern() {
        let date = DateUtils.getDate(forCSVDateString: "2026-01-27")
        let url = ParlVULinkBuilder.houseDebateURL(for: date)

        #expect(url?.absoluteString == "https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/2026-01-27/-1/39389")
    }

    @Test func powerBrowserURLRejectsMissingParts() {
        #expect(ParlVULinkBuilder.powerBrowserURL(dateSlug: "", eventID: "39389") == nil)
        #expect(ParlVULinkBuilder.powerBrowserURL(dateSlug: "2026-01-27", eventID: "") == nil)
    }

    @Test func normalizedURLHandlesProtocolRelativeOurCommonsEmbedLinks() {
        let url = ParlVULinkBuilder.normalizedURL(
            from: "//www.ourcommons.ca/embed/en/m/13388013?ml=en&amp;vt=watch&amp;autoplay=true"
        )

        #expect(url?.absoluteString == "https://www.ourcommons.ca/embed/en/m/13388013?ml=en&vt=watch&autoplay=true")
    }

    @Test func committeeWatchURLPrefersWebcastURL() {
        let webcastURL = URL(string: "https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/20260312/-1/44567")!
        let meeting = CommitteeMeeting(
            id: "PROC-45-1-25",
            committee: "PROC",
            committeeName: "Procedure and House Affairs",
            meetingNumber: 25,
            sessionNumber: 1,
            parliament: 45,
            date: nil,
            agendaItems: [],
            witnesses: [],
            webcastURL: webcastURL,
            publicationURL: URL(string: "https://www.ourcommons.ca/DocumentViewer/en/45-1/PROC/meeting-25/evidence"),
            evidenceURL: nil
        )

        #expect(ParlVULinkBuilder.committeeWatchURL(for: meeting) == webcastURL)
    }

    @Test func committeeWatchURLDoesNotInferFromTranscriptURL() {
        let meeting = CommitteeMeeting(
            id: "PROC-45-1-25",
            committee: "PROC",
            committeeName: "Procedure and House Affairs",
            meetingNumber: 25,
            sessionNumber: 1,
            parliament: 45,
            date: nil,
            agendaItems: [],
            witnesses: [],
            webcastURL: nil,
            publicationURL: URL(string: "https://www.ourcommons.ca/DocumentViewer/en/45-1/PROC/meeting-25/evidence"),
            evidenceURL: nil
        )

        #expect(ParlVULinkBuilder.committeeWatchURL(for: meeting) == nil)
    }
}
