@testable import epac
import Foundation
import Testing

struct CommitteesServiceTests {
	@Test func parsesUpcomingAndRecentMeetingsWithWitnesses() throws {
		let now = try #require(ISO8601DateFormatter().date(from: "2026-04-28T12:00:00Z"))
		let items: [[String: Any]] = [
			[
				"number": 42,
				"session": 1,
				"parliament": 45,
				"startDateTime": "2026-04-29T15:30:00Z",
				"committeeNameEn": "Finance",
				"agendaItems": [["titleEn": "Household Debt in Canada"]],
				"witnesses": [
					["nameEn": "Alex Chen", "organizationEn": "Bank of Canada"],
					["nameEn": "Maya Singh", "organizationEn": "Financial Consumer Agency of Canada"]
				],
				"webcastUrl": "//www.ourcommons.ca/embed/en/m/13388013?ml=en&amp;vt=watch"
			],
			[
				"meetingNumber": 41,
				"sessionNumber": 1,
				"parliament": 45,
				"date": "2026-04-27T15:30:00Z",
				"committeeNameEn": "Finance",
				"agendaItems": [["title": "Federal Spending Power"]]
			]
		]

		let result = CommitteesService.parseMeetings(items, committeeId: "FINA", parliament: 45, now: now)

		#expect(result.upcoming.map(\.meetingNumber) == [42])
		#expect(result.upcoming[0].agendaItems == ["Household Debt in Canada"])
		#expect(result.upcoming[0].witnesses.count == 2)
		#expect(result.upcoming[0].witnesses[0] == CommitteeWitness(name: "Alex Chen", organization: "Bank of Canada"))
		#expect(
			result.upcoming[0].webcastURL?.absoluteString
				== "https://www.ourcommons.ca/embed/en/m/13388013?ml=en&vt=watch"
		)
		#expect(result.recent.map(\.meetingNumber) == [41])
	}
}
