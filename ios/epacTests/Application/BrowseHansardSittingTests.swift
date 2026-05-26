@testable import epac
import Foundation
import Testing

@MainActor
struct BrowseHansardSittingTests {
	@Test func filtersSittingDatesToWindowSortsThemAndDoesNotFetchTranscripts() async throws {
		let before = Self.date(day: 1)
		let second = Self.date(day: 3)
		let first = Self.date(day: 2)
		let after = Self.date(day: 5)
		let repository = FixtureHansardRepository(
			sittingDates: [after, second, before, first, first]
		)
		let useCase = BrowseHansardSitting(repository: repository)

		let result = try await useCase.execute(
			jurisdiction: .federal,
			from: first,
			through: second
		)

		#expect(result.sittingDates == [first, second])
		#expect(repository.listRequests == [
			ListRequest(jurisdiction: .federal, startDate: first, endDate: second)
		])
		#expect(repository.fetchRequests.isEmpty)
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

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}
}
