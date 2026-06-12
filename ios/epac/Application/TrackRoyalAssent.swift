//
//  TrackRoyalAssent.swift
//  epac
//

import Foundation

@MainActor
struct TrackRoyalAssent: RecentLawQueryPort {
    private static let recentWindowDays = 30

    private let repository: any BillRepository
    private let clock: any Clock
    private let calendar: Calendar

    init(
        repository: any BillRepository,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.clock = clock
        self.calendar = calendar
    }

    func recentlyBecameLaw() async throws -> [Bill] {
        let bills = try await repository.fetchBills()
        let today = calendar.startOfDay(for: clock.now)
        let earliest = calendar.date(byAdding: .day, value: -Self.recentWindowDays, to: today) ?? today

        return bills
            .filter { bill in
                guard bill.status == .royalAssent,
                      let date = bill.becameLawDate else {
                    return false
                }
                let day = calendar.startOfDay(for: date)
                return day >= earliest && day <= today
            }
            .sorted { lhs, rhs in
                (lhs.becameLawDate ?? .distantPast) > (rhs.becameLawDate ?? .distantPast)
            }
    }
}
