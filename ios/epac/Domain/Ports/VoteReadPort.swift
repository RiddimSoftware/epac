//
//  VoteReadPort.swift
//  epac
//

import Foundation

/// Reads attendance and recorded-vote facts the daily digest needs.
/// Attendance is approximated from the day's recorded division counts
/// (yeas + nays + paired + absent) where available, since no separate
/// roll-call list is published.
@MainActor
protocol VoteReadPort: Sendable {
    func fetchAttendanceEstimate(for date: Date) async throws -> Double?
    func fetchVoteSummary(for date: Date) async throws -> DailyDigest.VoteSummary?
}
