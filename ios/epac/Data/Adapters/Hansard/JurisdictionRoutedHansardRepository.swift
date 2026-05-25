//
//  JurisdictionRoutedHansardRepository.swift
//  epac
//

import Foundation

@MainActor
struct JurisdictionRoutedHansardRepository: HansardRepository {
	private let adapters: [Jurisdiction: any HansardRepository]

	init(adapters: [Jurisdiction: any HansardRepository]) {
		self.adapters = adapters
	}

	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		try await adapter(for: jurisdiction).fetchTranscript(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate
		)
	}

	func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
		try await adapter(for: jurisdiction).listSittingDates(
			jurisdiction: jurisdiction,
			from: startDate,
			through: endDate
		)
	}

	func storeTranscript(_ transcript: HansardTranscript) async throws {
		try await adapter(for: transcript.jurisdiction).storeTranscript(transcript)
	}

	private func adapter(for jurisdiction: Jurisdiction) throws -> any HansardRepository {
		guard let adapter = adapters[jurisdiction] else {
			throw HansardAdapterError.unsupportedJurisdiction(jurisdiction)
		}
		return adapter
	}
}

enum HansardAdapterError: Error, Equatable {
	case unsupportedJurisdiction(Jurisdiction)
}
