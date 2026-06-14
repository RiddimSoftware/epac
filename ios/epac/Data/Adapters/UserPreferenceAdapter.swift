//
//  UserPreferenceAdapter.swift
//  epac
//
//  UserDefaults-backed adapter for the local user's notification preferences.
//

import Foundation

@MainActor
struct UserPreferenceAdapter: UserPreferenceReadPort {
    static let dailyDigestEnabledKey = "epac.notifications.dailyDigestEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreferences() async throws -> NotificationPreferences {
        NotificationPreferences(dailyDigestOptIn: defaults.bool(forKey: Self.dailyDigestEnabledKey))
    }
}
