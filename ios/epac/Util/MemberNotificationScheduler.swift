//
//  MemberNotificationScheduler.swift
//  epac
//
//  Schedules local UNUserNotificationCenter notifications for followed members
//  when new votes, speeches, or expenses are detected after a sync.
//
//  Must be called from MainActor context so MemberFollowStore.shared is accessible.
//

import Foundation
import UserNotifications

@MainActor
struct MemberNotificationScheduler {
    static func scheduleVoteNotification(memberName: String, ballot: String, description: String, memberID: Int) {
        guard MemberFollowStore.shared.preferences(for: memberID).votes else { return }
        let content = UNMutableNotificationContent()
        content.title = memberName
        content.body = String(format: NSLocalizedString("follow.notification.vote", comment: ""), ballot, description)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "vote-\(memberID)-\(description.hash)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleSpeechNotification(memberName: String, subject: String, memberID: Int) {
        guard MemberFollowStore.shared.preferences(for: memberID).speeches else { return }
        let content = UNMutableNotificationContent()
        content.title = memberName
        content.body = String(format: NSLocalizedString("follow.notification.speech", comment: ""), subject)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "speech-\(memberID)-\(subject.hash)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleExpenseNotification(memberName: String, quarter: Int, year: Int, memberID: Int) {
        guard MemberFollowStore.shared.preferences(for: memberID).expenses else { return }
        let content = UNMutableNotificationContent()
        content.title = memberName
        content.body = String(format: NSLocalizedString("follow.notification.expense", comment: ""), quarter, year)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "expense-\(memberID)-\(year)-\(quarter)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
