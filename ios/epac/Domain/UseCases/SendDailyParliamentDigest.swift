//
//  SendDailyParliamentDigest.swift
//  epac
//

import Foundation

@MainActor
public struct SendDailyParliamentDigest {
    private let hansardReadPort: any HansardReadPort
    private let voteReadPort: any VoteReadPort
    private let digestNotificationPort: any DigestNotificationPort
    private let userPreferenceReadPort: any UserPreferenceReadPort
    private let clock: any Clock

    public init(
        hansardReadPort: any HansardReadPort,
        voteReadPort: any VoteReadPort,
        digestNotificationPort: any DigestNotificationPort,
        userPreferenceReadPort: any UserPreferenceReadPort,
        clock: any Clock = SystemClock()
    ) {
        self.hansardReadPort = hansardReadPort
        self.voteReadPort = voteReadPort
        self.digestNotificationPort = digestNotificationPort
        self.userPreferenceReadPort = userPreferenceReadPort
        self.clock = clock
    }

    public func execute(startHour: Int = 17, endHour: Int = 23) async throws {
        // 1. Check user preference
        let user = try await userPreferenceReadPort.loadUser()
        guard user.dailyDigestOptIn else { return }

        let today = clock.now

        // 2. Timing boundary policy check
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: today)
        guard hour >= startHour && hour <= endHour else {
            return
        }

        // 3. Confirm sitting day
        guard try await hansardReadPort.isSittingDay(today) else { return }

        // 4. Fetch details
        let subjectCount = try await hansardReadPort.fetchSubjectsCount(for: today)
        let topSubjects = try await hansardReadPort.fetchTopSubjects(for: today, limit: 3)
        let attendance = try await voteReadPort.fetchAttendanceEstimate(for: today)
        let vote = try await voteReadPort.fetchVoteSummary(for: today)

        // 5. Compose digest
        let digest = DailyDigest(
            date: today,
            subjectCount: subjectCount,
            attendanceEstimate: attendance,
            topSubjects: topSubjects,
            vote: vote
        )

        // 6. Send push notification
        try await digestNotificationPort.sendNotification(for: digest)
    }
}
