//
//  HansardReadPort.swift
//  epac
//

import Foundation

/// Reads sitting-day facts the daily digest needs from Hansard.
/// Adapters resolve this from the backend's daily-Hansard endpoint or
/// from the locally cached SwiftData `Hansard` model.
@MainActor
protocol HansardReadPort: Sendable {
    func isSittingDay(_ date: Date) async throws -> Bool
    func fetchSubjectsCount(for date: Date) async throws -> Int
    func fetchTopSubjects(for date: Date, limit: Int) async throws -> [String]
}
