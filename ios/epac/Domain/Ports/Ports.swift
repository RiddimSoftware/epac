//
//  Ports.swift
//  epac
//

import Foundation

@MainActor
protocol HomeFeedRepository: Sendable {
    func fetchSittingDates() async throws -> [Date]
    func fetchAllMembers() async throws -> [HomeFollowedMember]
    func fetchMPActivityCount(for lastName: String) async throws -> Int
    func fetchLatestHansards(limit: Int) async throws -> [HomeHansardRecord]
    func fetchHansards(between start: Date, and end: Date) async throws -> [HomeHansardRecord]
    func fetchLatestVote() async throws -> HomeVoteRecord?
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> HomeMemberVoteRecord?
    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator]
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
