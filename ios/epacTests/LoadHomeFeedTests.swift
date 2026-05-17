//
//  LoadHomeFeedTests.swift
//  epacTests
//

@testable import epac
import XCTest

@MainActor
final class LoadHomeFeedTests: XCTestCase {

    func testLoadHomeFeedEmptyState() async throws {
        let clock = MockClock(date: Date())
        let repository = MockHomeFeedRepository()
        let onThisDay = MockOnThisDayFetching()
        let followPrefs = MockFollowPreferenceReading()

        let useCase = LoadHomeFeed(
            repository: repository,
            onThisDayFetching: onThisDay,
            followPreferenceReading: followPrefs,
            clock: clock
        )

        let snapshot = await useCase.execute()

        XCTAssertFalse(snapshot.isSittingToday)
        XCTAssertNil(snapshot.followedMember)
        XCTAssertEqual(snapshot.myMPActivityCount, 0)
        XCTAssertTrue(snapshot.recentSubjectTitles.isEmpty)
        XCTAssertTrue(snapshot.onThisDayItems.isEmpty)
        XCTAssertEqual(snapshot.civicContext.followedBills, [])
        XCTAssertEqual(snapshot.civicContext.followedTopics, [])
        XCTAssertEqual(snapshot.civicContext.mySenators.count, 0)
        XCTAssertEqual(snapshot.civicContext.provinceAbbrev, "")
        XCTAssertFalse(snapshot.hasPersonalizedContext)
    }

    func testLoadHomeFeedWithFollowedMPContext() async throws {
        let clock = MockClock(date: Date())
        let repository = MockHomeFeedRepository()
        let onThisDay = MockOnThisDayFetching()
        let followPrefs = MockFollowPreferenceReading(
            savedMemberName: "Jane Smith",
            followedBills: ["C-101"],
            followedTopics: ["topic-1"]
        )
        repository.membersToReturn = [
            HomeFollowedMember(memberID: 42, name: "Jane Smith", lastName: "Smith", provinceCode: "ON")
        ]
        repository.activityCountToReturn = 5
        repository.hansardsToReturn = [
            HomeHansardRecord(
                hansardID: "H-001",
                date: Date(),
                subjectRecords: [
                    HomeHansardRecord.SubjectRecord(
                        title: "Budget Debate",
                        messages: [
                            HomeHansardRecord.MessageRecord(lastName: "Smith", content: "Opening remarks on the budget.")
                        ]
                    )
                ]
            )
        ]

        let useCase = LoadHomeFeed(
            repository: repository,
            onThisDayFetching: onThisDay,
            followPreferenceReading: followPrefs,
            clock: clock
        )

        let snapshot = await useCase.execute()

        XCTAssertNotNil(snapshot.followedMember)
        XCTAssertEqual(snapshot.followedMember?.name, "Jane Smith")
        XCTAssertEqual(snapshot.myMPActivityCount, 5)
        XCTAssertTrue(snapshot.hasPersonalizedContext)
        XCTAssertEqual(snapshot.civicContext.followedBills, ["C-101"])
        XCTAssertEqual(snapshot.civicContext.followedTopics, ["topic-1"])
        XCTAssertEqual(snapshot.recentSubjectTitles, ["Budget Debate"])
        XCTAssertNotNil(snapshot.latestSpeechHighlight)
        XCTAssertEqual(snapshot.latestSpeechHighlight?.memberName, "Jane Smith")
        XCTAssertEqual(snapshot.latestSpeechHighlight?.subjectTitle, "Budget Debate")
    }

    func testOnThisDayPreservedOnFailure() async throws {
        let clock = MockClock(date: Date())
        let repository = MockHomeFeedRepository()
        let onThisDay = MockOnThisDayFetching(shouldThrow: true)
        let followPrefs = MockFollowPreferenceReading()

        let useCase = LoadHomeFeed(
            repository: repository,
            onThisDayFetching: onThisDay,
            followPreferenceReading: followPrefs,
            clock: clock
        )

        let existingItem = OnThisDayItem(
            id: "item-1", kind: .speech, year: 2024, date: "2024-01-15",
            title: "Budget speech 1924", excerpt: "The Minister moved...",
            speakerName: nil, memberID: nil, subjectTitle: nil,
            interventionID: nil, voteID: nil, billNumber: nil, sourceURL: nil
        )

        let snapshot = await useCase.execute(preservingOnThisDayItems: [existingItem])

        XCTAssertEqual(snapshot.onThisDayItems.count, 1)
        XCTAssertEqual(snapshot.onThisDayItems.first?.id, "item-1")
    }
}

// MARK: - Mocks

final class MockClock: Clock, @unchecked Sendable {
    let now: Date
    init(date: Date) { self.now = date }
}

@MainActor
class MockHomeFeedRepository: HomeFeedRepository {
    var membersToReturn: [HomeFollowedMember] = []
    var activityCountToReturn = 0
    var hansardsToReturn: [HomeHansardRecord] = []
    var voteToReturn: HomeVoteRecord?
    var memberVoteToReturn: HomeMemberVoteRecord?

    func fetchSittingDates() async throws -> [Date] { [] }
    func fetchAllMembers() async throws -> [HomeFollowedMember] { membersToReturn }
    func fetchMPActivityCount(for lastName: String) async throws -> Int { activityCountToReturn }
    func fetchLatestHansards(limit: Int) async throws -> [HomeHansardRecord] { hansardsToReturn }
    func fetchHansards(between start: Date, and end: Date) async throws -> [HomeHansardRecord] { [] }
    func fetchLatestVote() async throws -> HomeVoteRecord? { voteToReturn }
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> HomeMemberVoteRecord? { memberVoteToReturn }
    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator] { [] }
}

class MockOnThisDayFetching: OnThisDayFetching {
    private let shouldThrow: Bool
    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }
    func fetch(date: Date, limit: Int) async throws -> [OnThisDayItem] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return []
    }
}

@MainActor
class MockFollowPreferenceReading: FollowPreferenceReading {
    private let _savedMemberName: String?
    private let _followedBills: [String]
    private let _followedTopics: [String]

    init(savedMemberName: String? = nil, followedBills: [String] = [], followedTopics: [String] = []) {
        self._savedMemberName = savedMemberName
        self._followedBills = followedBills
        self._followedTopics = followedTopics
    }

    func followedBillNumbers() -> [String] { _followedBills }
    func followedTopicIDs() -> [String] { _followedTopics }
    func followedMemberIDs() -> [Int] { [] }
    func savedMemberName() -> String? { _savedMemberName }
    func dismissedOnThisDayDate() -> String? { nil }
    func dismissOnThisDay(dateString: String) {}
}
