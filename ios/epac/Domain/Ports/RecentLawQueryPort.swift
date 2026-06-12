//
//  RecentLawQueryPort.swift
//  epac
//

import Foundation

@MainActor
protocol RecentLawQueryPort: Sendable {
    func recentlyBecameLaw() async throws -> [Bill]
}
