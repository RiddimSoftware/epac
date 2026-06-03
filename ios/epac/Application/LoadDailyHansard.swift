//
//  LoadDailyHansard.swift
//  epac
//

import Foundation

@MainActor
struct LoadDailyHansard {
	private let repository: any HansardRepository
	private let telemetry: any TelemetryProvider

	init(
		repository: any HansardRepository,
		telemetry: any TelemetryProvider = CurrentTelemetryProvider()
	) {
		self.repository = repository
		self.telemetry = telemetry
	}

	func execute(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
		let span = telemetry.startSpan(
			name: PerformanceSignpostContract.SpanName.hansardFetchTranscript,
			operation: "hansard.fetch-transcript"
		)
		defer { span.finish() }

		let transcript = try await repository.fetchTranscript(
			jurisdiction: jurisdiction,
			sittingDate: sittingDate
		)
		try await repository.storeTranscript(transcript)
		return transcript
	}
}
