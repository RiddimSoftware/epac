//
//  LoadDailyHansard.swift
//  epac
//

import Foundation

@MainActor
struct LoadDailyHansard {
	private let repository: any HansardRepository

	init(repository: any HansardRepository) {
		self.repository = repository
	}

	func execute(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		let transcript = try await repository.fetchTranscript(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate
		)
		try await repository.storeTranscript(transcript)
		return transcript
	}
}
