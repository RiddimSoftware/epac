//
//  SittingRepository.swift
//  epac
//

import Foundation

@MainActor
protocol SittingRepository: Sendable {
    func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date]
    func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript
}
