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
        let followPrefs = MockFollowPreferenceReading()

        let useCase = LoadHomeFeed(
            repository: repository,
            followPreferenceReading: followPrefs,
            clock: clock
        )

        let snapshot = await useCase.execute()

        XCTAssertFalse(snapshot.isSittingToday)
        XCTAssertNil(snapshot.followedMember)
        XCTAssertEqual(snapshot.myMPActivityCount, 0)
        XCTAssertTrue(snapshot.recentSubjectTitles.isEmpty)
        XCTAssertEqual(snapshot.civicContext.followedBills, [])
        XCTAssertEqual(snapshot.civicContext.followedTopics, [])
        XCTAssertEqual(snapshot.civicContext.mySenators.count, 0)
        XCTAssertEqual(snapshot.civicContext.provinceAbbrev, "")
        XCTAssertFalse(snapshot.hasPersonalizedContext)
    }

    func testLoadHomeFeedWithFollowedMPContext() async throws {
        let clock = MockClock(date: Date())
        let repository = MockHomeFeedRepository()
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

    func testLoadHomeFeedIncludesProvinceSenateAppointments() async throws {
        let clock = MockClock(date: Date())
        let repository = MockHomeFeedRepository()
        let followPrefs = MockFollowPreferenceReading(savedMemberName: "Jane Smith")
        let appointmentDate = try XCTUnwrap(Self.dateFormatter.date(from: "2024-12-19"))
        let appointment = SenateAppointment(
            date: appointmentDate,
            appointingPrimeMinister: "Justin Trudeau",
            province: "ON",
            declaredAffiliation: "Independent Senators Group"
        )
        repository.membersToReturn = [
            HomeFollowedMember(memberID: 42, name: "Jane Smith", lastName: "Smith", provinceCode: "ON")
        ]
        repository.senatorsToReturn = [
            Senator(
                id: "test-senator-on",
                firstName: "Jane",
                lastName: "Senator",
                province: "ON",
                caucus: "ISG",
                caucusFullName: "Independent Senators Group",
                senateURL: URL(string: "https://sencanada.ca/en/senators/test")!,
                appointedDate: appointmentDate,
                appointment: appointment
            )
        ]

        let useCase = LoadHomeFeed(
            repository: repository,
            followPreferenceReading: followPrefs,
            clock: clock
        )

        let snapshot = await useCase.execute()

        XCTAssertEqual(snapshot.civicContext.provinceAbbrev, "ON")
        XCTAssertEqual(snapshot.civicContext.mySenators.count, 1)
        XCTAssertEqual(snapshot.civicContext.mySenators.first?.appointment?.appointingPrimeMinister, "Justin Trudeau")
        XCTAssertEqual(snapshot.civicContext.mySenators.first?.appointment?.declaredAffiliation, "Independent Senators Group")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
    var senatorsToReturn: [Senator] = []

    func fetchSittingDates() async throws -> [Date] { [] }
    func fetchAllMembers() async throws -> [HomeFollowedMember] { membersToReturn }
    func fetchMPActivityCount(for lastName: String) async throws -> Int { activityCountToReturn }
    func fetchLatestHansards(limit: Int) async throws -> [HomeHansardRecord] { hansardsToReturn }
    func fetchHansards(between start: Date, and end: Date) async throws -> [HomeHansardRecord] { [] }
    func fetchLatestVote() async throws -> HomeVoteRecord? { voteToReturn }
    func fetchMemberVote(memberID: Int, voteID: Int) async throws -> HomeMemberVoteRecord? { memberVoteToReturn }
    func fetchSenators(for provinceAbbrev: String) async throws -> [Senator] { senatorsToReturn }
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
}
