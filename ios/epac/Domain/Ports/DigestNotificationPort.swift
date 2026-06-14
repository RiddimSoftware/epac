//
//  DigestNotificationPort.swift
//  epac
//

import Foundation

@MainActor
public protocol DigestNotificationPort: Sendable {
    func sendNotification(for digest: DailyDigest) async throws
}
