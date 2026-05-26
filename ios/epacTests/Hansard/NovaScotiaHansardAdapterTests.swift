@testable import epac
import Foundation
import Testing

@MainActor
struct NovaScotiaHansardAdapterTests {
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
		day: TestDate.rangeStartDay
	).date!
	private static let endDate = DateComponents(
		calendar: .gregorianUTC,
		timeZone: .utc,
		year: TestDate.year,
		month: TestDate.month,
		day: TestDate.rangeEndDay
	).date!

	@Test func parsesNovaScotiaHansardTranscriptFixture() async throws {
		let adapter = Self.adapter()

		let transcript = try await adapter.fetchTranscript(jurisdiction: .novaScotia, sittingDate: Self.sittingDate)

		#expect(transcript.jurisdiction == .novaScotia)
		#expect(transcript.legislatureNumber == Expected.legislature)
		#expect(transcript.sourceURL.absoluteString.hasSuffix("/house_26feb24"))
		#expect(transcript.subjects.map(\.title).contains("PRESENTING AND READING PETITIONS"))
		#expect(transcript.subjects.map(\.title).contains("ORAL QUESTIONS PUT BY MEMBERS TO MINISTERS"))
		let speeches = transcript.subjects.flatMap(\.speeches)
		#expect(speeches.count >= Expected.minimumSpeechCount)
		#expect(Set(speeches.map(\.speakerName)).count >= Expected.minimumSpeakerCount)
		#expect(speeches.first?.interventionID.hasPrefix("speaker") == true)
		#expect(speeches.contains { speech in
			speech.interventionID == "susan-leblanc0005"
				&& speech.speakerName == "Susan Leblanc"
				&& speech.speakerMemberID == "susan-leblanc"
				&& speech.text.contains("sustainable ongoing funding")
		})
	}

	@Test func listsSittingDatesFromIndexFixtureWithinBounds() async throws {
		let adapter = Self.adapter()

		let dates = try await adapter.listSittingDates(
			jurisdiction: .novaScotia,
			from: Self.startDate,
			through: Self.endDate
		)

		#expect(dates == Expected.filteredFebruarySittingDates)
	}

	@Test func missingMemberProfileLinkKeepsSpeechWithoutMemberID() async throws {
		let html = try Self.transcriptHTML().replacingOccurrences(
			of: #"<a href="/members/profiles/susan-leblanc" class="hsd_mla" title="View Profile"> SUSAN LEBLANC</a>"#,
			with: #"<a title="View Profile"> SUSAN LEBLANC</a>"#
		)
		let adapter = Self.adapter(transcriptData: Data(html.utf8))

		let transcript = try await adapter.fetchTranscript(jurisdiction: .novaScotia, sittingDate: Self.sittingDate)
		let speech = transcript.subjects
			.flatMap(\.speeches)
			.first { $0.interventionID == "susan-leblanc0005" }

		#expect(speech?.speakerName == "Susan Leblanc")
		#expect(speech?.speakerMemberID == nil)
		#expect(speech?.text.contains("sustainable ongoing funding") == true)
	}

	@Test func storeDelegatesToPersistenceClosure() async throws {
		var stored: [HansardTranscript] = []
		let adapter = Self.adapter { transcript in
			stored.append(transcript)
		}
		let transcript = try await adapter.fetchTranscript(jurisdiction: .novaScotia, sittingDate: Self.sittingDate)

		try await adapter.storeTranscript(transcript)

		#expect(stored == [transcript])
	}

	private static func adapter(
		transcriptData: Data? = nil,
		persistTranscript: @escaping NovaScotiaHansardAdapter.PersistTranscript = { _ in }
	) -> NovaScotiaHansardAdapter {
		NovaScotiaHansardAdapter(
			fetchData: { url in
				try fixtureData(for: url, transcriptData: transcriptData)
			},
			sleep: { _ in },
			persistTranscript: persistTranscript
		)
	}

	nonisolated private static func fixtureData(for url: URL, transcriptData: Data?) throws -> Data {
		let urlString = url.absoluteString
		if urlString.contains("/house_26feb24") {
			if let transcriptData {
				return transcriptData
			}
			return try Data(contentsOf: fixtureURL("house_26feb24", extension: "html"))
		}
		if urlString.contains("/legislative-business/hansard-debates/assembly-65-session-1") {
			return try Data(contentsOf: fixtureURL("assembly-65-session-1-index", extension: "html"))
		}
		throw URLError(.fileDoesNotExist)
	}

	nonisolated private static func transcriptHTML() throws -> String {
		try String(contentsOf: fixtureURL("house_26feb24", extension: "html"), encoding: .utf8)
	}

	nonisolated private static func fixtureURL(_ name: String, extension pathExtension: String) -> URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/Hansard/NovaScotia/\(name).\(pathExtension)")
	}
}

private enum TestDate {
	static let year = 2026
	static let month = 2
	static let day = 24
	static let secondSittingDay = 25
	static let rangeStartDay = 24
	static let rangeEndDay = 26
}

private enum Expected {
	static let legislature = 65
	static let minimumSpeechCount = 100
	static let minimumSpeakerCount = 25
	static let filteredFebruarySittingDates: [Date] = [
		date(day: TestDate.day),
		date(day: TestDate.secondSittingDay),
		date(day: TestDate.rangeEndDay)
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
