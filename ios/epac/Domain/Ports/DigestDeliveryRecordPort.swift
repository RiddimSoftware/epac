//
//  DigestDeliveryRecordPort.swift
//  epac
//

import Foundation

/// Records and queries whether the daily Parliament digest was already
/// delivered on a given calendar day. Lets the use case avoid firing twice
/// when background refresh wakes the app multiple times within the digest
/// window.
@MainActor
protocol DigestDeliveryRecordPort: Sendable {
    func wasDelivered(on date: Date) async throws -> Bool
    func recordDelivered(on date: Date) async throws
}
