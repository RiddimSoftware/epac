//
//  SwiftDataHansardReadAdapter.swift
//  epac
//
//  Adapter for `HansardReadPort` backed by the local SwiftData store.
//  Treats a date as a *confirmed* sitting day only when a Hansard record exists
//  for it — i.e. the official record was published, not merely scheduled.
//

import Foundation
import SwiftData

@MainActor
struct SwiftDataHansardReadAdapter: HansardReadPort {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func isSittingDay(_ date: Date) async throws -> Bool {
        try hansard(for: date) != nil
    }

    func fetchSubjectsCount(for date: Date) async throws -> Int {
        guard let hansard = try hansard(for: date) else { return 0 }
        var seen: Set<String> = []
        for order in hansard.orders {
            for subject in order.subjects {
                seen.insert(subject.title)
            }
        }
        return seen.count
    }

    func fetchTopSubjects(for date: Date, limit: Int) async throws -> [String] {
        guard limit > 0, let hansard = try hansard(for: date) else { return [] }
        let stats = subjectStats(from: hansard)
        let ranked = stats.keys.sorted { lhs, rhs in
            let lhsStats = stats[lhs]
            let rhsStats = stats[rhs]
            if lhsStats?.speechCount != rhsStats?.speechCount {
                return (lhsStats?.speechCount ?? 0) > (rhsStats?.speechCount ?? 0)
            }
            return (lhsStats?.firstAppearance ?? .max) < (rhsStats?.firstAppearance ?? .max)
        }
        return Array(ranked.prefix(limit))
    }

    private struct SubjectStat {
        var speechCount: Int
        let firstAppearance: Int
    }

    private func subjectStats(from hansard: Hansard) -> [String: SubjectStat] {
        var stats: [String: SubjectStat] = [:]
        var index = 0
        for order in hansard.orders {
            for subject in order.subjects {
                let title = subject.title
                guard !title.isEmpty else { continue }
                if var existing = stats[title] {
                    existing.speechCount += subject.speeches.count
                    stats[title] = existing
                } else {
                    stats[title] = SubjectStat(speechCount: subject.speeches.count, firstAppearance: index)
                }
                index += 1
            }
        }
        return stats
    }

    private func hansard(for date: Date) throws -> Hansard? {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<Hansard>(
            predicate: #Predicate { $0.date >= day && $0.date < next }
        )
        return try modelContext.fetch(descriptor).first
    }
}
