@testable import epac
import Foundation
import Testing

@MainActor
struct LoadDailyHansardTests {
	@Test func fetchesAndStoresTranscript() async throws {
		let date = Self.date(day: 1)
		let transcript = Self.transcript(jurisdiction: .houseOfCommons, date: date)
		let repository = FixtureHansardRepository(transcripts: [transcript])
		let useCase = LoadDailyHansard(repository: repository)

		let result = try await useCase.execute(jurisdiction: .houseOfCommons, sittingDate: date)

		#expect(result == transcript)
		#expect(repository.fetchRequests.map(\.jurisdiction) == [.houseOfCommons])
		#expect(repository.fetchRequests.map(\.sittingDate) == [date])
		#expect(repository.storedTranscripts == [transcript])
	}

	@Test func propagatesFetchErrorWithoutStoring() async {
		let date = Self.date(day: 2)
		let repository = FixtureHansardRepository()
		repository.fetchError = FixtureHansardRepositoryError.fetchFailed
		let useCase = LoadDailyHansard(repository: repository)

		await #expect(throws: FixtureHansardRepositoryError.fetchFailed) {
			try await useCase.execute(jurisdiction: .houseOfCommons, sittingDate: date)
		}
		#expect(repository.storedTranscripts.isEmpty)
	}

	@Test func propagatesStoreError() async {
		let date = Self.date(day: 3)
		let transcript = Self.transcript(jurisdiction: .houseOfCommons, date: date)
		let repository = FixtureHansardRepository(transcripts: [transcript])
		repository.storeError = FixtureHansardRepositoryError.storeFailed
		let useCase = LoadDailyHansard(repository: repository)

		await #expect(throws: FixtureHansardRepositoryError.storeFailed) {
			try await useCase.execute(jurisdiction: .houseOfCommons, sittingDate: date)
		}
	}

	private static func transcript(jurisdiction: Jurisdiction, date: Date) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			hansardID: "h-\(Int(date.timeIntervalSince1970))",
			parliamentNumber: 45,
			sessionNumber: 1,
			orders: []
		)
	}

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}
}
