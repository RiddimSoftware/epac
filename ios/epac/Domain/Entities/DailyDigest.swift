//
//  DailyDigest.swift
//  epac
//

import Foundation

/// Factual summary of one sitting day, composed from official Hansard and recorded-vote data.
/// All fields trace to authoritative sources; nothing here is generated or paraphrased.
struct DailyDigest: Equatable, Sendable {
    let date: Date
    let subjectCount: Int
    let attendanceEstimate: Double?
    let topSubjects: [String]
    let vote: VoteSummary?

    struct VoteSummary: Equatable, Sendable {
        let billName: String
        let passed: Bool
        let yeas: Int
        let nays: Int
    }
}
