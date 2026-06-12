//
//  FollowedBill.swift
//  epac
//

import Foundation

struct FollowedBill: Equatable, Sendable {
    let billNumber: String
    let title: String
    let lastKnownStatus: String
    let lastKnownStage: String
}
