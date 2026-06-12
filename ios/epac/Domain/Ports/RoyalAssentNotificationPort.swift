//
//  RoyalAssentNotificationPort.swift
//  epac
//

import Foundation

@MainActor
protocol RoyalAssentNotificationPort: Sendable {
    func sendNotification(_ notification: Notification) async throws
}
