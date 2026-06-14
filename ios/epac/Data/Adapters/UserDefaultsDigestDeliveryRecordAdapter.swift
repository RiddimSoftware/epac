//
//  UserDefaultsDigestDeliveryRecordAdapter.swift
//  epac
//
//  Persists the calendar day on which the daily Parliament digest was last
//  delivered, so background refresh waking us multiple times within the
//  digest window cannot fire the same notification twice.
//

import Foundation

@MainActor
struct UserDefaultsDigestDeliveryRecordAdapter: DigestDeliveryRecordPort {
    static let lastDeliveredDayKey = "epac.notifications.dailyDigest.lastDeliveredDay"

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func wasDelivered(on date: Date) async throws -> Bool {
        guard let stored = defaults.object(forKey: Self.lastDeliveredDayKey) as? Date else {
            return false
        }
        return calendar.isDate(stored, inSameDayAs: date)
    }

    func recordDelivered(on date: Date) async throws {
        let dayStart = calendar.startOfDay(for: date)
        defaults.set(dayStart, forKey: Self.lastDeliveredDayKey)
    }
}
