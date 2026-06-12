//
//  FollowedBill.swift
//  epac
//
//  Created on 2026-06-12.
//

import Foundation

struct FollowedBill: Sendable, Identifiable {
    var id: String { number }
    let number: String
    let title: String
    let status: BillStatus
    let currentStage: String
    let lastUpdateTimestamp: Date
    let hasUnreadUpdate: Bool
    let bill: Bill?
}
