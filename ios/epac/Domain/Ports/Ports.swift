//
//  Ports.swift
//  epac
//

import Foundation

@MainActor
protocol HomeFeedRepository: Sendable {
    func fetchSittingCalendars() async throws -> [SittingCalendar]
    func fetchAllMembers() async throws -> [ParliamentMember]
    func fetchSpeechMessages(for lastName: String) async throws -> [SpeechMessage]
    func fetchLatestHansards(limit: Int) async throws -> [Hansard]
    func fetchHansards(between start: Date, and end: Date) async throws -> [Hansard]
    func fetchLatestRecordedVote() async throws -> RecordedVote?
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> MemberVote?
    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator]
}

protocol LiveParliamentStatusFetching: Sendable {
    func fetchStatus() async throws -> LiveParliamentStatus
}

protocol OnThisDayFetching: Sendable {
    func fetch(date: Date, limit: Int) async throws -> [OnThisDayItem]
}

@MainActor
protocol FollowPreferenceReading: Sendable {
    func followedBillNumbers() -> [String]
    func followedTopicIDs() -> [String]
    func followedMemberIDs() -> [Int]
    func savedMemberName() -> String?
    func dismissedOnThisDayDate() -> String?
    func dismissOnThisDay(dateString: String)
}

protocol Clock: Sendable {
    var now: Date { get }
}

struct SystemClock: Clock {
    init() {}
    var now: Date { Date() }
}
