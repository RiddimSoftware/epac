//
//  DailyDigest.swift
//  epac
//

import Foundation

public struct DailyDigest: Sendable, Equatable {
    public let date: Date
    public let subjectCount: Int
    public let attendanceEstimate: Double?
    public let topSubjects: [String]
    public let vote: VoteSummary?

    public struct VoteSummary: Sendable, Equatable {
        public let billName: String
        public let passed: Bool
        public let yeas: Int
        public let nays: Int

        public init(billName: String, passed: Bool, yeas: Int, nays: Int) {
            self.billName = billName
            self.passed = passed
            self.yeas = yeas
            self.nays = nays
        }
    }

    public init(
        date: Date,
        subjectCount: Int,
        attendanceEstimate: Double?,
        topSubjects: [String],
        vote: VoteSummary?
    ) {
        self.date = date
        self.subjectCount = subjectCount
        self.attendanceEstimate = attendanceEstimate
        self.topSubjects = topSubjects
        self.vote = vote
    }
}
