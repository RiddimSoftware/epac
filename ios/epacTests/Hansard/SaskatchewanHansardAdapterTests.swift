@testable import epac
import Foundation
import Testing

@MainActor
struct SaskatchewanHansardAdapterTests {
	private static let sittingDate = DateComponents(
		calendar: .gregorianUTC,
		timeZone: .utc,
		year: TestDate.year,
		month: TestDate.month,
		day: TestDate.day
	).date!
	private static let startDate = DateComponents(
		calendar: .gregorianUTC,
		timeZone: .utc,
		year: TestDate.year,
		month: TestDate.month,
		day: TestDate.monthStartDay
	).date!
	private static let endDate = DateComponents(
		calendar: .gregorianUTC,
		timeZone: .utc,
		year: TestDate.year,
		month: TestDate.month,
		day: TestDate.monthEndDay
	).date!

	@Test func parsesSaskatchewanHansardTranscriptFixture() async throws {
		let adapter = Self.adapter()

		let transcript = try await adapter.fetchTranscript(jurisdiction: .saskatchewan, sittingDate: Self.sittingDate)

		#expect(transcript.jurisdiction == .saskatchewan)
		#expect(transcript.legislatureNumber == Expected.legislature)
		#expect(transcript.subjects.map(\.title).contains("INTRODUCTION OF GUESTS"))
		#expect(transcript.subjects.map(\.title).contains("QUESTION PERIOD"))
		let speeches = transcript.subjects.flatMap(\.speeches)
		#expect(speeches.count >= Expected.minimumSpeechCount)
		#expect(Set(speeches.map(\.speakerName)).count >= Expected.minimumSpeakerCount)
		#expect(speeches.first?.interventionID.hasPrefix("sk-") == true)
		#expect(speeches.contains { $0.speakerName == "Speaker Goudy" })
		#expect(speeches.contains { $0.speakerName == "Michael Weger" })
	}

	@Test func listsSittingDatesFromMonthIndexFixture() async throws {
		let adapter = Self.adapter()

		let dates = try await adapter.listSittingDates(
			jurisdiction: .saskatchewan,
			from: Self.startDate,
			through: Self.endDate
		)

		#expect(dates == Expected.maySittingDates)
	}

	@Test func keepsLongQuotedPassageAttributedToSpeaker() async throws {
		let adapter = Self.adapter()

		let transcript = try await adapter.fetchTranscript(jurisdiction: .saskatchewan, sittingDate: Self.sittingDate)
		let speech = transcript.subjects
			.flatMap(\.speeches)
			.first { $0.text.contains("You’re going to win some and you’re going to lose some") }

		#expect(speech?.speakerName == "Michael Weger")
		#expect(speech?.text.contains("Coach McMillan") == true)
		#expect(speech?.text.contains("you shouldn’t be in the business") == true)
	}

	@Test func storeDelegatesToPersistenceClosure() async throws {
		var stored: [HansardTranscript] = []
		let adapter = Self.adapter { transcript in
			stored.append(transcript)
		}
		let transcript = try await adapter.fetchTranscript(jurisdiction: .saskatchewan, sittingDate: Self.sittingDate)

		try await adapter.storeTranscript(transcript)

		#expect(stored == [transcript])
	}

	private static func adapter(
		persistTranscript: @escaping SaskatchewanHansardAdapter.PersistTranscript = { _ in }
	) -> SaskatchewanHansardAdapter {
		SaskatchewanHansardAdapter(
			fetchData: { url in
				try fixtureData(for: url)
			},
			sleep: { _ in },
			persistTranscript: persistTranscript
		)
	}

	nonisolated private static func fixtureData(for url: URL) throws -> Data {
		let urlString = url.absoluteString
		if urlString.contains("/legislative-business/archive/") {
			return try Data(contentsOf: fixtureURL("may-2026-index", extension: "html"))
		}
		if urlString.hasSuffix("20260514Debates-HTML.htm") {
			return try Data(contentsOf: fixtureURL("20260514Debates-HTML", extension: "htm"))
		}
		throw URLError(.fileDoesNotExist)
	}

	nonisolated private static func fixtureURL(_ name: String, extension pathExtension: String) -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/Saskatchewan/\(name).\(pathExtension)")
	}
}

private enum TestDate {
	static let year = 2026
	static let month = 5
	static let day = 14
	static let monthStartDay = 1
	static let monthEndDay = 31
}

private enum Expected {
	static let legislature = 30
	static let minimumSpeechCount = 50
	static let minimumSpeakerCount = 10
	static let maySittingDates: [Date] = [
		date(day: MaySittingDay.fourth),
		date(day: MaySittingDay.fifth),
		date(day: MaySittingDay.sixth),
		date(day: MaySittingDay.seventh),
		date(day: MaySittingDay.eleventh),
		date(day: MaySittingDay.twelfth),
		date(day: MaySittingDay.thirteenth),
		date(day: MaySittingDay.fourteenth)
	]

	private static func date(day: Int) -> Date {
		DateComponents(
			calendar: .gregorianUTC,
			timeZone: .utc,
			year: TestDate.year,
			month: TestDate.month,
			day: day
		).date!
	}
}

private enum MaySittingDay {
	static let fourth = 4
	static let fifth = 5
	static let sixth = 6
	static let seventh = 7
	static let eleventh = 11
	static let twelfth = 12
	static let thirteenth = 13
	static let fourteenth = 14
}

private extension Calendar {
	static var gregorianUTC: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .utc
		return calendar
	}
}

private extension TimeZone {
	static let utc = TimeZone(secondsFromGMT: 0)!
}
