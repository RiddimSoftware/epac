//
//  SendDailyParliamentDigestTests.swift
//  epacTests
//

@testable import epac
import XCTest

@MainActor
final class SendDailyParliamentDigestTests: XCTestCase {

    struct MockClock: Clock {
        let now: Date
    }

    func testExecuteWhenNotOptedInDoesNotSend() async throws {
        let userPreference = MockUserPreferenceReadPort(user: User(dailyDigestOptIn: false))
        let hansardRead = MockHansardReadPort(isSittingDay: true, subjectsCount: 5, topSubjects: ["Subj 1"])
        let voteRead = MockVoteReadPort(attendance: 0.85, voteSummary: nil)
        let notificationPort = MockDigestNotificationPort()

        let date = createDate(hour: 18)
        let clock = MockClock(now: date)

        let useCase = SendDailyParliamentDigest(
            hansardReadPort: hansardRead,
            voteReadPort: voteRead,
            digestNotificationPort: notificationPort,
            userPreferenceReadPort: userPreference,
            clock: clock
        )

        try await useCase.execute()

        XCTAssertNil(notificationPort.sentDigest)
    }

    func testExecuteWhenOutsideTimingWindowDoesNotSend() async throws {
        let userPreference = MockUserPreferenceReadPort(user: User(dailyDigestOptIn: true))
        let hansardRead = MockHansardReadPort(isSittingDay: true, subjectsCount: 5, topSubjects: ["Subj 1"])
        let voteRead = MockVoteReadPort(attendance: 0.85, voteSummary: nil)
        let notificationPort = MockDigestNotificationPort()

        let date = createDate(hour: 15) // 3 PM is outside 5-11 PM (17:00-23:00)
        let clock = MockClock(now: date)

        let useCase = SendDailyParliamentDigest(
            hansardReadPort: hansardRead,
            voteReadPort: voteRead,
            digestNotificationPort: notificationPort,
            userPreferenceReadPort: userPreference,
            clock: clock
        )

        try await useCase.execute()

        XCTAssertNil(notificationPort.sentDigest)
    }

    func testExecuteWhenNotSittingDayDoesNotSend() async throws {
        let userPreference = MockUserPreferenceReadPort(user: User(dailyDigestOptIn: true))
        let hansardRead = MockHansardReadPort(isSittingDay: false, subjectsCount: 0, topSubjects: [])
        let voteRead = MockVoteReadPort(attendance: nil, voteSummary: nil)
        let notificationPort = MockDigestNotificationPort()

        let date = createDate(hour: 19)
        let clock = MockClock(now: date)

        let useCase = SendDailyParliamentDigest(
            hansardReadPort: hansardRead,
            voteReadPort: voteRead,
            digestNotificationPort: notificationPort,
            userPreferenceReadPort: userPreference,
            clock: clock
        )

        try await useCase.execute()

        XCTAssertNil(notificationPort.sentDigest)
    }

    func testExecuteSuccessSendsDigest() async throws {
        let userPreference = MockUserPreferenceReadPort(user: User(dailyDigestOptIn: true))
        let hansardRead = MockHansardReadPort(isSittingDay: true, subjectsCount: 12, topSubjects: ["Agriculture", "Finance", "Housing"])
        let voteRead = MockVoteReadPort(
            attendance: 0.92,
            voteSummary: DailyDigest.VoteSummary(billName: "C-234", passed: true, yeas: 180, nays: 120)
        )
        let notificationPort = MockDigestNotificationPort()

        let date = createDate(hour: 20)
        let clock = MockClock(now: date)

        let useCase = SendDailyParliamentDigest(
            hansardReadPort: hansardRead,
            voteReadPort: voteRead,
            digestNotificationPort: notificationPort,
            userPreferenceReadPort: userPreference,
            clock: clock
        )

        try await useCase.execute()

        XCTAssertNotNil(notificationPort.sentDigest)
        let digest = notificationPort.sentDigest!
        XCTAssertEqual(digest.date, date)
        XCTAssertEqual(digest.subjectCount, 12)
        XCTAssertEqual(digest.attendanceEstimate, 0.92)
        XCTAssertEqual(digest.topSubjects, ["Agriculture", "Finance", "Housing"])
        XCTAssertEqual(digest.vote?.billName, "C-234")
        XCTAssertTrue(digest.vote?.passed ?? false)
        XCTAssertEqual(digest.vote?.yeas, 180)
        XCTAssertEqual(digest.vote?.nays, 120)
    }

    // Helper
    private func createDate(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 12
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}

@MainActor
class MockUserPreferenceReadPort: UserPreferenceReadPort {
    let user: User
    init(user: User) { self.user = user }
    func loadUser() async throws -> User { return user }
}

@MainActor
class MockHansardReadPort: HansardReadPort {
    let sittingDay: Bool
    let count: Int
    let top: [String]

    init(isSittingDay: Bool, subjectsCount: Int, topSubjects: [String]) {
        self.sittingDay = isSittingDay
        self.count = subjectsCount
        self.top = topSubjects
    }

    func fetchSubjectsCount(for date: Date) async throws -> Int { return count }
    func fetchTopSubjects(for date: Date, limit: Int) async throws -> [String] { return top }
    func isSittingDay(_ date: Date) async throws -> Bool { return sittingDay }
}

@MainActor
class MockVoteReadPort: VoteReadPort {
    let attendance: Double?
    let summary: DailyDigest.VoteSummary?

    init(attendance: Double?, voteSummary: DailyDigest.VoteSummary?) {
        self.attendance = attendance
        self.summary = voteSummary
    }

    func fetchAttendanceEstimate(for date: Date) async throws -> Double? { return attendance }
    func fetchVoteSummary(for date: Date) async throws -> DailyDigest.VoteSummary? { return summary }
}

@MainActor
class MockDigestNotificationPort: DigestNotificationPort {
    var sentDigest: DailyDigest?

    func sendNotification(for digest: DailyDigest) async throws {
        sentDigest = digest
    }
}
