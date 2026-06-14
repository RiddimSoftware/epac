//
//  UserPreferenceReadPort.swift
//  epac
//

import Foundation

@MainActor
public protocol UserPreferenceReadPort: Sendable {
    func loadUser() async throws -> User
}
