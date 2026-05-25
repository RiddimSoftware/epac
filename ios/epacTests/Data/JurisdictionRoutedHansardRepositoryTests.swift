@testable import epac
import Foundation
import Testing

@MainActor
struct JurisdictionRoutedHansardRepositoryTests {
	private static let federalDate = Date(timeIntervalSince1970: 1_800_000_000)
	private static let albertaDate = Date(timeIntervalSince1970: 1_800_100_000)

	@Test func dispatchesFetchToFederalAdapter() async throws {
		let transcript = Self.transcript(jurisdiction: .federal, date: Self.federalDate)
		let federal = FixtureHansardRepository(transcripts: [transcript])
		let router = JurisdictionRoutedHansardRepository(adapters: [.federal: federal])

		let result = try await router.fetchTranscript(jurisdiction: .federal, sittingDate: Self.federalDate)

		#expect(result == transcript)
		#expect(federal.fetchRequests.count == 1)
		#expect(federal.fetchRequests[0].jurisdiction == .federal)
	}

	@Test func dispatchesListToFederalAdapter() async throws {
		let start = Self.federalDate
		let end = Date(timeIntervalSince1970: 1_800_200_000)
		let federal = FixtureHansardRepository(sittingDates: [start])
		let router = JurisdictionRoutedHansardRepository(adapters: [.federal: federal])

		let dates = try await router.listSittingDates(jurisdiction: .federal, from: start, through: end)

		#expect(dates == [start])
		#expect(federal.listRequests.count == 1)
	}

	@Test func dispatchesStoreToCorrectAdapter() async throws {
		let transcript = Self.transcript(jurisdiction: .federal, date: Self.federalDate)
		let federal = FixtureHansardRepository()
		let router = JurisdictionRoutedHansardRepository(adapters: [.federal: federal])

		try await router.storeTranscript(transcript)

		#expect(federal.storedTranscripts == [transcript])
	}

	@Test func throwsForUnknownJurisdiction() async {
		let federal = FixtureHansardRepository()
		let router = JurisdictionRoutedHansardRepository(adapters: [.federal: federal])

		await #expect(throws: HansardAdapterError.unsupportedJurisdiction(.alberta)) {
			try await router.fetchTranscript(jurisdiction: .alberta, sittingDate: Self.albertaDate)
		}
	}

	@Test func throwsForUnknownJurisdictionOnList() async {
		let router = JurisdictionRoutedHansardRepository(adapters: [:])

		await #expect(throws: HansardAdapterError.unsupportedJurisdiction(.novaScotia)) {
			try await router.listSittingDates(
				jurisdiction: .novaScotia,
				from: Self.federalDate,
				through: Self.albertaDate
			)
		}
	}

	@Test func multiAdapterRegistrationDispatchesCorrectly() async throws {
		let federalTranscript = Self.transcript(jurisdiction: .federal, date: Self.federalDate)
		let albertaTranscript = Self.transcript(jurisdiction: .alberta, date: Self.albertaDate)
		let federal = FixtureHansardRepository(transcripts: [federalTranscript])
		let alberta = FixtureHansardRepository(transcripts: [albertaTranscript])
		let router = JurisdictionRoutedHansardRepository(adapters: [
			.federal: federal,
			.alberta: alberta
		])

		let fedResult = try await router.fetchTranscript(jurisdiction: .federal, sittingDate: Self.federalDate)
		let abResult = try await router.fetchTranscript(jurisdiction: .alberta, sittingDate: Self.albertaDate)

		#expect(fedResult == federalTranscript)
		#expect(abResult == albertaTranscript)
		#expect(federal.fetchRequests.count == 1)
		#expect(alberta.fetchRequests.count == 1)
	}

	@Test func registrationOrderDoesNotAffectDispatch() async throws {
		let federalTranscript = Self.transcript(jurisdiction: .federal, date: Self.federalDate)
		let albertaTranscript = Self.transcript(jurisdiction: .alberta, date: Self.albertaDate)
		let federal = FixtureHansardRepository(transcripts: [federalTranscript])
		let alberta = FixtureHansardRepository(transcripts: [albertaTranscript])

		let routerAB = JurisdictionRoutedHansardRepository(adapters: [
			.alberta: alberta,
			.federal: federal
		])

		let fedResult = try await routerAB.fetchTranscript(jurisdiction: .federal, sittingDate: Self.federalDate)
		let abResult = try await routerAB.fetchTranscript(jurisdiction: .alberta, sittingDate: Self.albertaDate)

		#expect(fedResult == federalTranscript)
		#expect(abResult == albertaTranscript)
	}

	private static func transcript(jurisdiction: Jurisdiction, date: Date) -> HansardTranscript {
		HansardTranscript(
			jurisdiction: jurisdiction,
			sittingDate: date,
			parliamentNumber: jurisdiction == .federal ? 45 : nil,
			sessionNumber: jurisdiction == .federal ? 1 : nil,
			legislatureNumber: jurisdiction == .federal ? nil : 31,
			sourceURL: URL(string: "https://example.com/hansard/\(jurisdiction.rawValue)/\(Int(date.timeIntervalSince1970))")!,
			language: Locale(identifier: "en-CA"),
			subjects: []
		)
	}
}
