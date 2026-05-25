//
//  HansardRepository.swift
//  epac
//

import Foundation

@MainActor
protocol HansardRepository: Sendable {
	func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript
	func listSittingDates(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> [Date]
	func storeTranscript(_ transcript: HansardTranscript) async throws
}
