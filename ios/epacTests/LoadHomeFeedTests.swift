//
//  LoadHomeFeedTests.swift
//  epacTests
//

import XCTest
@testable import epac
import SwiftData

@MainActor
final class LoadHomeFeedTests: XCTestCase {
    
    func testLoadHomeFeedEmptyState() async throws {
        let clock = SystemClock()
        // Wait, testing requires mock ports. Since we need to write "given the user has no personalized context, when tests exercise the use case, then the empty/home setup state remains equivalent to current behavior"
        // Let's create mocks inside the test file.
        let repository = MockHomeFeedRepository()
        let liveStatus = MockLiveParliamentStatusFetching()
        let onThisDay = MockOnThisDayFetching()
        let followPrefs = MockFollowPreferenceReading()
        
        let useCase = LoadHomeFeed(
            repository: repository,
            liveParliamentStatusFetching: liveStatus,
            onThisDayFetching: onThisDay,
            followPreferenceReading: followPrefs,
            clock: clock
        )
        
        let snapshot = await useCase.execute()
        
        XCTAssertFalse(snapshot.isSittingToday)
        XCTAssertNil(snapshot.followedMember)
        XCTAssertEqual(snapshot.myMPActivityCount, 0)
        XCTAssertTrue(snapshot.recentSubjects.isEmpty)
        XCTAssertTrue(snapshot.onThisDayItems.isEmpty)
        XCTAssertEqual(snapshot.civicContext.followedBills, [])
        XCTAssertEqual(snapshot.civicContext.followedTopics, [])
        XCTAssertEqual(snapshot.civicContext.mySenators.count, 0)
        XCTAssertEqual(snapshot.civicContext.provinceAbbrev, "")
    }
}

// Mocks

@MainActor
class MockHomeFeedRepository: HomeFeedRepository {
    func fetchSittingCalendars() async throws -> [SittingCalendar] { [] }
    func fetchAllMembers() async throws -> [ParliamentMember] { [] }
    func fetchSpeechMessages(for lastName: String) async throws -> [SpeechMessage] { [] }
    func fetchLatestHansards(limit: Int) async throws -> [Hansard] { [] }
    func fetchHansards(between start: Date, and end: Date) async throws -> [Hansard] { [] }
    func fetchLatestRecordedVote() async throws -> RecordedVote? { nil }
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> MemberVote? { nil }
    func fetchSenators() async throws -> [Senator] { [] }
}

class MockLiveParliamentStatusFetching: LiveParliamentStatusFetching {
    func fetchStatus() async throws -> LiveParliamentStatus {
        LiveParliamentStatus(
            status: .unknown,
            isSitting: false,
            businessType: "Unknown",
            currentItemTitle: nil,
            currentBillNumber: nil,
            currentSpeakerName: nil,
            divisionInProgress: false,
            checkedAt: Date(),
            lastChangedAt: nil,
            sittingDate: nil,
            sourceURL: URL(string: "https://example.com")!
        )
    }
}

class MockOnThisDayFetching: OnThisDayFetching {
    func fetch(date: Date, limit: Int) async throws -> [OnThisDayItem] { [] }
}

@MainActor
class MockFollowPreferenceReading: FollowPreferenceReading {
    func followedBillNumbers() -> [String] { [] }
    func followedTopicIDs() -> [String] { [] }
    func savedMemberName() -> String? { nil }
    func dismissedOnThisDayDate() -> String? { nil }
    func dismissOnThisDay(dateString: String) {}
}
