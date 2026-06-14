//
//  SwiftDataVoteReadAdapter.swift
//  epac
//
//  Adapter for `VoteReadPort` backed by the local SwiftData store. Reads the
//  federal recorded divisions held on a date to estimate attendance and
//  surface the day's top vote summary.
//

import Foundation
import SwiftData

@MainActor
struct SwiftDataVoteReadAdapter: VoteReadPort {
    static let houseOfCommonsSeats = 338

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let totalSeats: Int

    init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        totalSeats: Int = SwiftDataVoteReadAdapter.houseOfCommonsSeats
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.totalSeats = totalSeats
    }

    func fetchAttendanceEstimate(for date: Date) async throws -> Double? {
        let votes = try federalVotes(for: date)
        guard !votes.isEmpty, totalSeats > 0 else { return nil }
        let participation = votes.map { Double($0.yea + $0.nay + $0.paired) / Double(totalSeats) }
        let average = participation.reduce(0, +) / Double(participation.count)
        return min(max(average, 0), 1)
    }

    func fetchVoteSummary(for date: Date) async throws -> DailyDigest.VoteSummary? {
        let votes = try federalVotes(for: date)
        guard let vote = votes.first else { return nil }
        let passed = vote.resultEn.lowercased().contains("agreed")
        let billName = vote.billNumberCode.isEmpty ? vote.descriptionEn : vote.billNumberCode
        return DailyDigest.VoteSummary(
            billName: billName,
            passed: passed,
            yeas: vote.yea,
            nays: vote.nay
        )
    }

    private func federalVotes(for date: Date) throws -> [RecordedVote] {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let federal = Jurisdiction.federal.rawValue
        let descriptor = FetchDescriptor<RecordedVote>(
            predicate: #Predicate { $0.jurisdiction == federal && $0.date >= day && $0.date < next },
            sortBy: [SortDescriptor(\.number)]
        )
        return try modelContext.fetch(descriptor)
    }
}
