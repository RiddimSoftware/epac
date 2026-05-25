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
		guard let subject = transcript.subjects.first(where: { $0.hansardID == subjectID }) else {
			return []
		}

		return subject.speeches
			.sorted(by: Self.speechPrecedes)
			.flatMap { speech in
				speech.messages.sorted(by: Self.messagePrecedes)
			}
	}

	private static func speechPrecedes(_ lhs: HansardSpeechRecord, _ rhs: HansardSpeechRecord) -> Bool {
		let lhsFirstMessage = lhs.messages.min(by: messagePrecedes)
		let rhsFirstMessage = rhs.messages.min(by: messagePrecedes)
		if let lhsFirstMessage, let rhsFirstMessage {
			return messagePrecedes(lhsFirstMessage, rhsFirstMessage)
		}
		return lhs.hansardID.caseInsensitiveCompare(rhs.hansardID) == .orderedAscending
	}

	private static func messagePrecedes(_ lhs: SpeechMessageRecord, _ rhs: SpeechMessageRecord) -> Bool {
		lhs.hansardID.caseInsensitiveCompare(rhs.hansardID) == .orderedAscending
	}
}
