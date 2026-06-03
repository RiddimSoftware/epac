@testable import epac
import Foundation
import Testing

@MainActor
struct LoadDailyHansardTests {
	@Test func fetchesAndStoresTranscript() async throws {
		let date = Self.date(day: 1)
		let transcript = Self.transcript(jurisdiction: .federal, date: date)
		let repository = FixtureHansardRepository(transcripts: [transcript])
		let useCase = LoadDailyHansard(repository: repository)

		let result = try await useCase.execute(jurisdiction: .federal, sittingDate: date)

		#expect(result == transcript)
		#expect(repository.fetchRequests.map(\.jurisdiction) == [.federal])
		#expect(repository.fetchRequests.map(\.sittingDate) == [date])
		#expect(repository.storedTranscripts == [transcript])
	}

	@Test func fetchTranscriptIsTimedThroughTelemetryProvider() async throws {
		let date = Self.date(day: 4)
		let transcript = Self.transcript(jurisdiction: .federal, date: date)
		let repository = FixtureHansardRepository(transcripts: [transcript])
		let telemetry = RecordingTelemetryProvider()
		let useCase = LoadDailyHansard(repository: repository, telemetry: telemetry)

		_ = try await useCase.execute(jurisdiction: .federal, sittingDate: date)

		#expect(telemetry.store.spans.count == 1)
		#expect(telemetry.store.spans.first?.name == PerformanceSignpostContract.SpanName.hansardFetchTranscript)
		#expect(telemetry.store.spans.first?.operation == "hansard.fetch-transcript")
	}

	@Test func propagatesFetchErrorWithoutStoring() async {
		let date = Self.date(day: 2)
		let repository = FixtureHansardRepository()
		repository.fetchError = FixtureHansardRepositoryError.fetchFailed
		let useCase = LoadDailyHansard(repository: repository)

		await #expect(throws: FixtureHansardRepositoryError.fetchFailed) {
			try await useCase.execute(jurisdiction: .federal, sittingDate: date)
		}
		#expect(repository.storedTranscripts.isEmpty)
	}

	@Test func propagatesStoreError() async {
		let date = Self.date(day: 3)
		let transcript = Self.transcript(jurisdiction: .federal, date: date)
		let repository = FixtureHansardRepository(transcripts: [transcript])
		repository.storeError = FixtureHansardRepositoryError.storeFailed
		let useCase = LoadDailyHansard(repository: repository)

		await #expect(throws: FixtureHansardRepositoryError.storeFailed) {
			try await useCase.execute(jurisdiction: .federal, sittingDate: date)
		}
	}

	private static func transcript(jurisdiction: Jurisdiction, date: Date) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			parliamentNumber: 45,
			sessionNumber: 1,
			legislatureNumber: nil,
			sourceURL: Self.sourceURL(for: date),
			language: Locale(identifier: "en-CA"),
			subjects: []
		)
	}

	private static func date(day: Int) -> Date {
		Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
	}

	private static func sourceURL(for date: Date) -> URL {
		URL(string: "https://example.com/hansard/\(Int(date.timeIntervalSince1970))")!
	}
}
