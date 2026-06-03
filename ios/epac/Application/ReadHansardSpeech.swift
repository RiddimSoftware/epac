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
	private let repository: any SittingRepository
	private let telemetry: any TelemetryProvider

	init(
		repository: any SittingRepository,
		telemetry: any TelemetryProvider = CurrentTelemetryProvider()
	) {
		self.repository = repository
		self.telemetry = telemetry
	}

	func execute(
		jurisdiction: Jurisdiction,
		sittingDate: Date,
		subjectID: String
	) async throws -> [SpeechMessageRecord] {
		let span = telemetry.startSpan(
			name: PerformanceSignpostContract.SpanName.hansardFetchTranscript,
			operation: "hansard.fetch-transcript"
		)
		defer { span.finish() }

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
