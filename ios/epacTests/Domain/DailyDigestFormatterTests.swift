//
//  DailyDigestFormatterTests.swift
//  epacTests
//

@testable import epac
import Foundation
import Testing

struct DailyDigestFormatterTests {

    @Test func bodyJoinsHeadlineFieldsWithMiddot() {
        let digest = DailyDigest(
            date: date(year: 2026, month: 6, day: 12),
            subjectCount: 9,
            attendanceEstimate: 0.92,
            topSubjects: ["Housing", "Healthcare", "Climate"],
            vote: nil
        )

        let body = DailyDigestFormatter.body(for: digest)

        #expect(body.contains("9 debates"))
        #expect(body.contains("92% of MPs present"))
        #expect(body.contains("Housing, Healthcare, Climate"))
        #expect(body.contains(" · "))
    }

    @Test func bodyOmitsAttendanceWhenUnknown() {
        let digest = DailyDigest(
            date: date(year: 2026, month: 6, day: 12),
            subjectCount: 4,
            attendanceEstimate: nil,
            topSubjects: ["Trade"],
            vote: nil
        )

        let body = DailyDigestFormatter.body(for: digest)

        #expect(!body.contains("% of MPs present"))
        #expect(body.contains("4 debates"))
        #expect(body.contains("Trade"))
    }

    @Test func bodyOmitsTopSubjectsLineWhenEmpty() {
        let digest = DailyDigest(
            date: date(year: 2026, month: 6, day: 12),
            subjectCount: 2,
            attendanceEstimate: 0.5,
            topSubjects: [],
            vote: nil
        )

        let body = DailyDigestFormatter.body(for: digest)

        #expect(body.contains("2 debates"))
        #expect(body.contains("50% of MPs present"))
    }

    @Test func bodyAppendsVoteLineForPassedVote() {
        let digest = DailyDigest(
            date: date(year: 2026, month: 6, day: 12),
            subjectCount: 9,
            attendanceEstimate: 0.92,
            topSubjects: ["Housing"],
            vote: DailyDigest.VoteSummary(billName: "C-234", passed: true, yeas: 180, nays: 120)
        )

        let body = DailyDigestFormatter.body(for: digest)

        #expect(body.contains("C-234"))
        #expect(body.contains("passed"))
        #expect(body.contains("180–120"))
        #expect(body.contains("\n"))
    }

    @Test func bodyAppendsVoteLineForDefeatedVote() {
        let digest = DailyDigest(
            date: date(year: 2026, month: 6, day: 12),
            subjectCount: 9,
            attendanceEstimate: 0.92,
            topSubjects: ["Housing"],
            vote: DailyDigest.VoteSummary(billName: "C-99", passed: false, yeas: 120, nays: 180)
        )

        let body = DailyDigestFormatter.body(for: digest)

        #expect(body.contains("C-99"))
        #expect(body.contains("defeated"))
        #expect(body.contains("120–180"))
    }

    @Test func titleIncludesFormattedDate() {
        let title = DailyDigestFormatter.title(for: date(year: 2026, month: 6, day: 12))

        #expect(title.contains("Parliament sat today"))
        #expect(title.contains("2026"))
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
}
