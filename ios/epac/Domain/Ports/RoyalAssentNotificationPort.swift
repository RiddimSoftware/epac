//
//  RoyalAssentNotificationPort.swift
//  epac
//

import Foundation

@MainActor
protocol RoyalAssentNotificationPort: Sendable {
    func sendNotification(_ notification: RoyalAssentNotification) async throws
}
