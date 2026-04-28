//
//  ParliamentTodayIntent.swift
//  epac
//

import AppIntents
import SwiftData

// Answers "Is Parliament sitting today?" from cached SittingCalendar data.
// Opens epac so the user can see the full schedule.
struct ParliamentTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Parliament Today"
    static let description = IntentDescription("Check whether the House of Commons is sitting today.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let today = Calendar.current.startOfDay(for: Date())
        let isSitting = isSittingDay(today)
        let dialog: IntentDialog = isSitting
            ? "Yes, the House of Commons is sitting today."
            : "No, the House of Commons is not sitting today."
        return .result(dialog: dialog)
    }

    // Checks the cached sitting calendar stored in UserDefaults by Fetch.downloadCalendar.
    private func isSittingDay(_ date: Date) -> Bool {
        guard let stored = UserDefaults.standard.array(forKey: "calendardates_v2") as? [Date] else {
            return false
        }
        let cal = Calendar.current
        return stored.contains { cal.isDate($0, inSameDayAs: date) }
    }
}
