//
//  DigestNotificationPort.swift
//  epac
//

import Foundation

/// Delivers a composed `DailyDigest` to the user as a notification.
/// Implementations format the digest into title/body text and hand it
/// to the platform's notification surface (e.g. UNUserNotificationCenter).
@MainActor
protocol DigestNotificationPort: Sendable {
    func send(_ digest: DailyDigest) async throws
}
