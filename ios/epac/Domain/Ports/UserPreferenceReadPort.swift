//
//  UserPreferenceReadPort.swift
//  epac
//

import Foundation

/// Reads the local user's notification preferences.
@MainActor
protocol UserPreferenceReadPort: Sendable {
    func loadPreferences() async throws -> NotificationPreferences
}
