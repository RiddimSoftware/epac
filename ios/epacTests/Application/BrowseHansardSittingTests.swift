@testable import epac
import Foundation
import Testing

@MainActor
struct BrowseHansardSittingTests {
	@Test func filtersSittingDatesToWindowAndSortsThem() async throws {
		let before = Self.date(day: 1)
		let second = Self.date(day: 3)
		let first = Self.date(day: 2)
		let after = Self.date(day: 5)
		let repository = FixtureHansardRepository(
			transcripts: [
				Self.transcript(date: first, subjects: []),
				Self.transcript(date: second, subjects: [])
			],
			sittingDates: [after, second, before, first, first]
		)
		let useCase = BrowseHansardSitting(repository: repository)

			let result = try await useCase.execute(
				jurisdiction: .federal,
				from: first,
				through: second
			)

		#expect(result.sittingDates == [first, second])
		#expect(result.sittings.map(\.sittingDate) == [first, second])
	}

	@Test func aggregatesSubjectsForEachSittingDate() async throws {
		let first = Self.date(day: 7)
		let second = Self.date(day: 8)
		let firstTranscript = Self.transcript(date: first, subjects: [
			Self.subject(id: "s1", title: "Housing"),
			Self.subject(id: "s2", title: "Finance")
		])
		let secondTranscript = Self.transcript(date: second, subjects: [
			Self.subject(id: "s3", title: "Environment")
		])
		let repository = FixtureHansardRepository(
			transcripts: [firstTranscript, secondTranscript],
			sittingDates: [first, second]
		)
		let useCase = BrowseHansardSitting(repository: repository)

			let result = try await useCase.execute(
				jurisdiction: .federal,
				from: first,
				through: second
			)

		#expect(result.sittings[0].subjects.map(\.title) == ["Housing", "Finance"])
		#expect(result.sittings[1].subjects.map(\.title) == ["Environment"])
	}

	@Test func propagatesListSittingDateErrors() async {
		let repository = FixtureHansardRepository()
		repository.listError = FixtureHansardRepositoryError.listFailed
		let useCase = BrowseHansardSitting(repository: repository)

		await #expect(throws: FixtureHansardRepositoryError.listFailed) {
				try await useCase.execute(
					jurisdiction: .federal,
					from: Self.date(day: 1),
					through: Self.date(day: 2)
				)
		}
	}

	private static func transcript(date: Date, subjects: [SubjectOfBusinessRecord]) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: .federal,
			sittingDate: date,
			parliamentNumber: 45,
			sessionNumber: 1,
			legislatureNumber: nil,
			sourceURL: Self.sourceURL(for: date),
			language: Locale(identifier: "en-CA"),
			subjects: subjects
		)
	}

	private static func subject(id: String, title: String) -> SubjectOfBusinessRecord {
		SubjectOfBusinessRecord(id: id, title: title, speeches: [])
	}

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}

	private static func sourceURL(for date: Date) -> URL {
		URL(string: "https://example.com/hansard/\(Int(date.timeIntervalSince1970))")!
	}
}
