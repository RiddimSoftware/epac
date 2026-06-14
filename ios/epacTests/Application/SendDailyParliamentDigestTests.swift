//
//  SendDailyParliamentDigestTests.swift
//  epacTests
//

@testable import epac
import Foundation
import Testing

@MainActor
struct SendDailyParliamentDigestTests {

    @Test func skipsWhenUserHasNotOptedIn() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 9, topSubjects: ["A", "B", "C"]),
            voteReadPort: VoteReadStub(attendance: 0.92, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: false)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 19)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.isEmpty)
    }

    @Test func skipsBefore5PM() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 9, topSubjects: ["A"]),
            voteReadPort: VoteReadStub(attendance: 0.85, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 16, minute: 59)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.isEmpty)
    }

    @Test func skipsAfter11PM() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 9, topSubjects: ["A"]),
            voteReadPort: VoteReadStub(attendance: 0.85, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 23, minute: 59)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.isEmpty)
    }

    @Test func skipsOnNonSittingDay() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: false, subjectCount: 0, topSubjects: []),
            voteReadPort: VoteReadStub(attendance: nil, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 19)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.isEmpty)
    }

    @Test func sendsDigestOnSittingDayInsideWindow() async throws {
        let now = Self.localDate(hour: 19)
        let notifier = DigestNotificationSpy()
        let deliveryRecord = DeliveryRecordSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(
                isSittingDay: true,
                subjectCount: 12,
                topSubjects: ["Agriculture", "Finance", "Housing"]
            ),
            voteReadPort: VoteReadStub(
                attendance: 0.92,
                voteSummary: DailyDigest.VoteSummary(
                    billName: "C-234",
                    passed: true,
                    yeas: 180,
                    nays: 120
                )
            ),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: deliveryRecord,
            clock: FixedClock(now: now),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.count == 1)
        let digest = try #require(notifier.sentDigests.first)
        #expect(digest.date == now)
        #expect(digest.subjectCount == 12)
        #expect(digest.attendanceEstimate == 0.92)
        #expect(digest.topSubjects == ["Agriculture", "Finance", "Housing"])
        #expect(digest.vote?.billName == "C-234")
        #expect(digest.vote?.passed == true)
        #expect(digest.vote?.yeas == 180)
        #expect(digest.vote?.nays == 120)
        #expect(deliveryRecord.recordedDates.count == 1)
    }

    @Test func passesTopSubjectsLimitOfThreeToHansardPort() async throws {
        let hansard = HansardReadStub(isSittingDay: true, subjectCount: 5, topSubjects: ["A"])
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: hansard,
            voteReadPort: VoteReadStub(attendance: 0.5, voteSummary: nil),
            digestNotificationPort: DigestNotificationSpy(),
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 19)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(hansard.lastTopSubjectsLimit == 3)
    }

    @Test func sendsAtStartHourBoundary() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 1, topSubjects: ["X"]),
            voteReadPort: VoteReadStub(attendance: nil, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 17, minute: 0)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.count == 1)
    }

    @Test func sendsAtEndHourBoundary() async throws {
        let notifier = DigestNotificationSpy()
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 1, topSubjects: ["X"]),
            voteReadPort: VoteReadStub(attendance: nil, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: DeliveryRecordSpy(),
            clock: FixedClock(now: Self.localDate(hour: 23, minute: 0)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.count == 1)
    }

    @Test func skipsWhenAlreadyDeliveredToday() async throws {
        let notifier = DigestNotificationSpy()
        let deliveryRecord = DeliveryRecordSpy(alreadyDeliveredOnDate: Self.localDate(hour: 17))
        let useCase = SendDailyParliamentDigest(
            hansardReadPort: HansardReadStub(isSittingDay: true, subjectCount: 1, topSubjects: ["X"]),
            voteReadPort: VoteReadStub(attendance: nil, voteSummary: nil),
            digestNotificationPort: notifier,
            userPreferenceReadPort: UserPreferenceStub(user: NotificationPreferences(dailyDigestOptIn: true)),
            deliveryRecordPort: deliveryRecord,
            clock: FixedClock(now: Self.localDate(hour: 19)),
            calendar: Self.fixedCalendar
        )

        try await useCase.execute()

        #expect(notifier.sentDigests.isEmpty)
        #expect(deliveryRecord.recordedDates.isEmpty)
    }

    // MARK: - Calendar helpers

    private static let fixedCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    private static func localDate(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 12
        components.hour = hour
        components.minute = minute
        return fixedCalendar.date(from: components)!
    }
}

// MARK: - Stubs / Spies

@MainActor
private struct UserPreferenceStub: UserPreferenceReadPort {
    let preferences: NotificationPreferences

    init(user: NotificationPreferences) {
        self.preferences = user
    }

    func loadPreferences() async throws -> NotificationPreferences { preferences }
}

@MainActor
private final class HansardReadStub: HansardReadPort {
    let isSittingDayResult: Bool
    let subjectCountResult: Int
    let topSubjectsResult: [String]
    private(set) var lastTopSubjectsLimit: Int?

    init(isSittingDay: Bool, subjectCount: Int, topSubjects: [String]) {
        self.isSittingDayResult = isSittingDay
        self.subjectCountResult = subjectCount
        self.topSubjectsResult = topSubjects
    }

    func isSittingDay(_ date: Date) async throws -> Bool { isSittingDayResult }
    func fetchSubjectsCount(for date: Date) async throws -> Int { subjectCountResult }
    func fetchTopSubjects(for date: Date, limit: Int) async throws -> [String] {
        lastTopSubjectsLimit = limit
        return Array(topSubjectsResult.prefix(limit))
    }
}

@MainActor
private struct VoteReadStub: VoteReadPort {
    let attendance: Double?
    let voteSummary: DailyDigest.VoteSummary?

    func fetchAttendanceEstimate(for date: Date) async throws -> Double? { attendance }
    func fetchVoteSummary(for date: Date) async throws -> DailyDigest.VoteSummary? { voteSummary }
}

@MainActor
private final class DigestNotificationSpy: DigestNotificationPort {
    private(set) var sentDigests: [DailyDigest] = []

    func send(_ digest: DailyDigest) async throws {
        sentDigests.append(digest)
    }
}

@MainActor
private final class DeliveryRecordSpy: DigestDeliveryRecordPort {
    private(set) var recordedDates: [Date] = []
    private var alreadyDeliveredOnDate: Date?
    private let calendar: Calendar

    init(alreadyDeliveredOnDate: Date? = nil) {
        self.alreadyDeliveredOnDate = alreadyDeliveredOnDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        self.calendar = calendar
    }

    func wasDelivered(on date: Date) async throws -> Bool {
        guard let already = alreadyDeliveredOnDate else { return false }
        return calendar.isDate(already, inSameDayAs: date)
    }

    func recordDelivered(on date: Date) async throws {
        recordedDates.append(date)
        alreadyDeliveredOnDate = date
    }
}

private struct FixedClock: Clock {
    let now: Date
}
