//
//  DailyDigestFormatter.swift
//  epac
//
//  Pure, framework-free composer for the title and body of the daily Parliament
//  digest notification. Extracted from the notification adapter so it can be
//  unit-tested without UNUserNotificationCenter.
//

import Foundation

enum DailyDigestFormatter {
    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static func title(for date: Date) -> String {
        String(
            format: NSLocalizedString("dailyDigest.notification.title", comment: ""),
            titleDateFormatter.string(from: date)
        )
    }

    static func body(for digest: DailyDigest) -> String {
        var lines: [String] = []
        lines.append(headlineLine(for: digest))
        if let vote = digest.vote {
            lines.append(voteLine(for: vote))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func headlineLine(for digest: DailyDigest) -> String {
        let debates = String(
            format: NSLocalizedString("dailyDigest.notification.debates", comment: ""),
            digest.subjectCount
        )

        var pieces = [debates]

        if let share = digest.attendanceEstimate {
            let percent = Int((share * 100).rounded())
            pieces.append(
                String(
                    format: NSLocalizedString("dailyDigest.notification.attendance", comment: ""),
                    percent
                )
            )
        }

        if !digest.topSubjects.isEmpty {
            pieces.append(digest.topSubjects.joined(separator: ", "))
        }

        return pieces.joined(separator: " · ")
    }

    private static func voteLine(for vote: DailyDigest.VoteSummary) -> String {
        let outcomeKey = vote.passed
            ? "dailyDigest.notification.vote.passed"
            : "dailyDigest.notification.vote.defeated"
        let outcome = NSLocalizedString(outcomeKey, comment: "")
        return String(
            format: NSLocalizedString("dailyDigest.notification.vote.line", comment: ""),
            vote.billName,
            outcome,
            vote.yeas,
            vote.nays
        )
    }
}
