//
//  FollowedBillReadPort.swift
//  epac
//
//  Created on 2026-06-12.
//

import Foundation

struct FollowedBillRecord: Sendable {
    let number: String
    let lastKnownStatus: String
    let lastKnownStage: String
    let followedAt: Date
    let hasUnreadUpdate: Bool
}

@MainActor
protocol FollowedBillReadPort: Sendable {
    func fetchFollowedBills() async throws -> [FollowedBillRecord]
}
