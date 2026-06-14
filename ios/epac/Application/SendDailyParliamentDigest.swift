//
//  SendDailyParliamentDigest.swift
//  epac
//

import Foundation

/// Composes and delivers the once-per-sitting-day Parliament digest notification
/// for opted-in users. All content traces to the official record (Hansard +
/// recorded divisions); nothing is generated or paraphrased.
///
/// The timing window (default 17:00–23:00 local) and sitting-day check are
/// expressed as use-case-layer policy rather than scheduler implementation
/// detail, so the same use case can be driven by background refresh, a future
/// push-receipt handler, or a manual debug trigger.
@MainActor
struct SendDailyParliamentDigest {
    static let defaultStartHour = 17
    static let defaultEndHour = 23
    static let topSubjectsLimit = 3
    private static let minutesPerHour = 60

    private let hansardReadPort: any HansardReadPort
    private let voteReadPort: any VoteReadPort
    private let digestNotificationPort: any DigestNotificationPort
    private let userPreferenceReadPort: any UserPreferenceReadPort
    private let deliveryRecordPort: any DigestDeliveryRecordPort
    private let clock: any Clock
    private let calendar: Calendar

    init(
        hansardReadPort: any HansardReadPort,
        voteReadPort: any VoteReadPort,
        digestNotificationPort: any DigestNotificationPort,
        userPreferenceReadPort: any UserPreferenceReadPort,
        deliveryRecordPort: any DigestDeliveryRecordPort,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.hansardReadPort = hansardReadPort
        self.voteReadPort = voteReadPort
        self.digestNotificationPort = digestNotificationPort
        self.userPreferenceReadPort = userPreferenceReadPort
        self.deliveryRecordPort = deliveryRecordPort
        self.clock = clock
        self.calendar = calendar
    }

    func execute(
        startHour: Int = Self.defaultStartHour,
        endHour: Int = Self.defaultEndHour
    ) async throws {
        let preferences = try await userPreferenceReadPort.loadPreferences()
        guard preferences.dailyDigestOptIn else { return }

        let now = clock.now
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutesSinceMidnight = (components.hour ?? 0) * Self.minutesPerHour + (components.minute ?? 0)
        let windowStart = startHour * Self.minutesPerHour
        let windowEnd = endHour * Self.minutesPerHour
        guard minutesSinceMidnight >= windowStart, minutesSinceMidnight <= windowEnd else { return }

        guard try await hansardReadPort.isSittingDay(now) else { return }

        if try await deliveryRecordPort.wasDelivered(on: now) { return }

        let subjectCount = try await hansardReadPort.fetchSubjectsCount(for: now)
        let topSubjects = try await hansardReadPort.fetchTopSubjects(
            for: now,
            limit: Self.topSubjectsLimit
        )
        let attendance = try await voteReadPort.fetchAttendanceEstimate(for: now)
        let vote = try await voteReadPort.fetchVoteSummary(for: now)

        let digest = DailyDigest(
            date: now,
            subjectCount: subjectCount,
            attendanceEstimate: attendance,
            topSubjects: topSubjects,
            vote: vote
        )

        try await digestNotificationPort.send(digest)
        try await deliveryRecordPort.recordDelivered(on: now)
    }
}
