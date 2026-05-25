import SwiftUI

private struct HansardRepositoryEnvironmentKey: EnvironmentKey {
	static let defaultValue: any HansardRepository = UnsupportedHansardRepository()
}

extension EnvironmentValues {
	var hansardRepository: any HansardRepository {
		get { self[HansardRepositoryEnvironmentKey.self] }
		set { self[HansardRepositoryEnvironmentKey.self] = newValue }
	}
}

private struct UnsupportedHansardRepository: HansardRepository {
	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		throw HansardAdapterError.unsupportedJurisdiction(transcript.jurisdiction)
	}
}
