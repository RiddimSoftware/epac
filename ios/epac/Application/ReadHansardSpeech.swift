//
//  ReadHansardSpeech.swift
//  epac
//

import Foundation

@MainActor
protocol ReadHansardSpeechUseCase: Sendable {
	func execute(
		jurisdiction: Jurisdiction,
		sittingDate: Date,
		subjectID: String
	) async throws -> [SpeechMessageRecord]
}

@MainActor
struct ReadHansardSpeech: ReadHansardSpeechUseCase {
	private let repository: any HansardRepository

	init(repository: any HansardRepository) {
		self.repository = repository
	}

	func execute(
		jurisdiction: Jurisdiction,
		sittingDate: Date,
		subjectID: String
	) async throws -> [SpeechMessageRecord] {
		let transcript = try await repository.fetchTranscript(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate
		)
		guard let subject = transcript.subjects.first(where: { $0.id == subjectID }) else {
			return []
		}

		return subject.speeches.sorted(by: Self.messagePrecedes)
	}

	private static func messagePrecedes(_ lhs: SpeechMessageRecord, _ rhs: SpeechMessageRecord) -> Bool {
		lhs.interventionID.caseInsensitiveCompare(rhs.interventionID) == .orderedAscending
	}
}
