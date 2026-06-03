//
//  HansardSittingRepositoryAdapter.swift
//  epac
//

import Foundation

@MainActor
struct HansardSittingRepositoryAdapter: SittingRepository {
    private let hansardRepository: any HansardRepository

    init(hansardRepository: any HansardRepository) {
        self.hansardRepository = hansardRepository
    }

    func listSittingDates(jurisdiction: Jurisdiction, from startDate: Date, through endDate: Date) async throws -> [Date] {
        try await hansardRepository.listSittingDates(jurisdiction: jurisdiction, from: startDate, through: endDate)
    }

    func fetchTranscript(jurisdiction: Jurisdiction, sittingDate: Date) async throws -> HansardTranscript {
        try await hansardRepository.fetchTranscript(jurisdiction: jurisdiction, sittingDate: sittingDate)
    }
}
