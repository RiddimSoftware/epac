//
//  UserPreferenceAdapter.swift
//  epac
//

import Foundation

@MainActor
public final class UserPreferenceAdapter: UserPreferenceReadPort {
    public init() {}

    public func loadUser() async throws -> User {
        let optIn = UserDefaults.standard.bool(forKey: "epac.notifications.dailyDigestEnabled")
        return User(dailyDigestOptIn: optIn)
    }
}
