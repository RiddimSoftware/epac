@testable import epac
import Foundation
import Testing

@MainActor
struct OntarioHansardAdapterTests {
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

	@Test func parsesOntarioXMLTranscriptFixture() async throws {
		let adapter = Self.adapter(useXMLFixture: true)

		let transcript = try await adapter.fetchTranscript(jurisdiction: .ontario, sittingDate: Self.sittingDate)

		#expect(transcript.jurisdiction == .ontario)
		#expect(transcript.parliamentNumber == Expected.parliament)
		#expect(transcript.sessionNumber == Expected.session)
		#expect(transcript.sourceURL.absoluteString.hasSuffix("/2025-05-01/hansard.xml"))
		#expect(transcript.subjects.map(\.title).contains("Orders of the Day"))
		#expect(transcript.subjects.map(\.title).contains("Statements by the Ministry and Responses"))
		let speeches = transcript.subjects.flatMap(\.speeches)
		#expect(speeches.count == Expected.xmlSpeechCount)
		#expect(Set(speeches.map(\.speakerName)).count == Expected.xmlSpeakerCount)
		#expect(speeches.first?.interventionID == "on-xml-2025-05-01-P255_15151")
		#expect(speeches.first?.speakerName == "Jamie West")
		#expect(speeches.first?.speakerMemberID == "mpp-jamie-west")
	}

	@Test func parsesOntarioHTMLFallbackTranscriptFixture() async throws {
		let adapter = Self.adapter(useXMLFixture: false)

		let transcript = try await adapter.fetchTranscript(jurisdiction: .ontario, sittingDate: Self.sittingDate)

		#expect(transcript.jurisdiction == .ontario)
		#expect(transcript.parliamentNumber == Expected.parliament)
		#expect(transcript.sessionNumber == Expected.session)
		#expect(transcript.sourceURL.absoluteString.hasSuffix("/2025-05-01/hansard"))
		#expect(transcript.subjects.contains { $0.title.hasPrefix("Protect Ontario by Unleashing our Economy Act") })
		#expect(transcript.subjects.map(\.title).contains("Mental health services"))
		let speeches = transcript.subjects.flatMap(\.speeches)
		#expect(speeches.count >= Expected.minimumHTMLSpeechCount)
		#expect(Set(speeches.map(\.speakerName)).count >= Expected.minimumHTMLSpeakerCount)
		#expect(speeches.contains { $0.interventionID == "on-P255_15151" })
		#expect(speeches.contains { $0.speakerName == "Jamie West" })
	}

	@Test func listsSittingDatesFromOntarioSessionIndexFixture() async throws {
		let adapter = Self.adapter()

		let dates = try await adapter.listSittingDates(
			jurisdiction: .ontario,
			from: Self.startDate,
			through: Self.endDate
		)

		#expect(dates == Expected.maySittingDates)
	}

	@Test func keepsLongFormMinisterialStatementContinuationParagraphsAttributedToSpeaker() async throws {
		let adapter = Self.adapter(useXMLFixture: true)

		let transcript = try await adapter.fetchTranscript(jurisdiction: .ontario, sittingDate: Self.sittingDate)
		let speech = transcript.subjects
			.flatMap(\.speeches)
			.first { $0.text.contains("second continuation paragraph") }

		#expect(speech?.speakerName == "Example Minister")
		#expect(speech?.text.contains("first continuation paragraph") == true)
		#expect(speech?.text.contains("second continuation paragraph") == true)
	}

	@Test func keepsHTMLContinuationParagraphsAttributedToSpeaker() async throws {
		let adapter = Self.adapter(useXMLFixture: false)

		let transcript = try await adapter.fetchTranscript(jurisdiction: .ontario, sittingDate: Self.sittingDate)
		let speech = transcript.subjects
			.flatMap(\.speeches)
			.first { $0.text.contains("one project, one process") }

		#expect(speech?.speakerName == "Jamie West")
		#expect(speech?.text.contains("government has committed") == true)
		#expect(speech?.text.contains("six out of 229 pages") == true)
	}

	@Test func storeDelegatesToPersistenceClosure() async throws {
		var stored: [HansardTranscript] = []
		let adapter = Self.adapter { transcript in
			stored.append(transcript)
		}
		let transcript = try await adapter.fetchTranscript(jurisdiction: .ontario, sittingDate: Self.sittingDate)

		try await adapter.storeTranscript(transcript)

		#expect(stored == [transcript])
	}

	private static func adapter(
		useXMLFixture: Bool = true,
		persistTranscript: @escaping OntarioHansardAdapter.PersistTranscript = { _ in }
	) -> OntarioHansardAdapter {
		OntarioHansardAdapter(
			fetchData: { url in
				try fixtureData(for: url, useXMLFixture: useXMLFixture)
			},
			sleep: { _ in },
			persistTranscript: persistTranscript
		)
	}

	nonisolated private static func fixtureData(for url: URL, useXMLFixture: Bool) throws -> Data {
		let urlString = url.absoluteString
		if useXMLFixture, urlString.hasSuffix("/2025-05-01/hansard.xml") {
			return try Data(contentsOf: fixtureURL("2025-05-01-hansard", extension: "xml"))
		}
		if urlString.hasSuffix("/2025-05-01/hansard") {
			return try Data(contentsOf: fixtureURL("2025-05-01-hansard", extension: "html"))
		}
		if urlString.hasSuffix("/parliament-44/session-1") {
			return try Data(contentsOf: fixtureURL("parliament-44-session-1-index", extension: "html"))
		}
		throw URLError(.fileDoesNotExist)
	}

	nonisolated private static func fixtureURL(_ name: String, extension pathExtension: String) -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/Ontario/\(name).\(pathExtension)")
	}
}

private enum TestDate {
	static let year = int("2025")
	static let month = int("5")
	static let day = int("1")
	static let monthStartDay = int("1")
	static let monthEndDay = int("31")

	private static func int(_ value: String) -> Int {
		Int(value) ?? 0
	}
}

private enum Expected {
	static let parliament = int("44")
	static let session = int("1")
	static let xmlSpeechCount = int("3")
	static let xmlSpeakerCount = int("3")
	static let minimumHTMLSpeechCount = int("100")
	static let minimumHTMLSpeakerCount = int("20")
	static let maySittingDates: [Date] = [
		date(day: MaySittingDay.first),
		date(day: MaySittingDay.fifth),
		date(day: MaySittingDay.sixth),
		date(day: MaySittingDay.seventh),
		date(day: MaySittingDay.eighth),
		date(day: MaySittingDay.twelfth),
		date(day: MaySittingDay.thirteenth),
		date(day: MaySittingDay.fourteenth),
		date(day: MaySittingDay.fifteenth),
		date(day: MaySittingDay.twentySixth),
		date(day: MaySittingDay.twentySeventh),
		date(day: MaySittingDay.twentyEighth),
		date(day: MaySittingDay.twentyNinth)
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

	private static func int(_ value: String) -> Int {
		Int(value) ?? 0
	}
}

private enum MaySittingDay {
	static let first = int("1")
	static let fifth = int("5")
	static let sixth = int("6")
	static let seventh = int("7")
	static let eighth = int("8")
	static let twelfth = int("12")
	static let thirteenth = int("13")
	static let fourteenth = int("14")
	static let fifteenth = int("15")
	static let twentySixth = int("26")
	static let twentySeventh = int("27")
	static let twentyEighth = int("28")
	static let twentyNinth = int("29")

	private static func int(_ value: String) -> Int {
		Int(value) ?? 0
	}
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
