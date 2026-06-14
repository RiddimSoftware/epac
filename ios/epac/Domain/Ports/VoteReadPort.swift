//
//  VoteReadPort.swift
//  epac
//

import Foundation

@MainActor
public protocol VoteReadPort: Sendable {
    func fetchAttendanceEstimate(for date: Date) async throws -> Double?
    func fetchVoteSummary(for date: Date) async throws -> DailyDigest.VoteSummary?
}
