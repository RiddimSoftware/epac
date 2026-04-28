//
//  TopicNotificationScheduler.swift
//  epac
//
//  Fires local notifications when new Hansard subjects or bills match
//  any topic the user is following. Call sites are on MainActor so
//  TopicFollowStore.shared is safe to access.
//
//  Identification uses a djb2 hash (same as MemberNotificationScheduler)
//  so UNNotificationCenter can deduplicate across app launches.
//

import Foundation
import UserNotifications

@MainActor
struct TopicNotificationScheduler {

    // MARK: - Public entry points

    /// Call after new Hansard subjects are added to SwiftData.
    static func checkAndNotify(subjectTitles: [(title: String, date: Date)]) {
        guard NotificationPreferenceStore.shared.topicConsultations else { return }
        let store = TopicFollowStore.shared
        guard !store.followedIDs.isEmpty else { return }
        for item in subjectTitles {
            let dateSlug = DateUtils.getCSVStringFromDate(item.date)
            for topic in store.matchingFollowedTopics(for: item.title) {
                schedule(
                    topicName: topic.localizedName,
                    contentTitle: item.title,
                    source: NSLocalizedString("topic.source.debate", comment: ""),
                    identifier: "topic-\(topic.id)-\(dateSlug)-\(stableID(item.title))"
                )
            }
        }
    }

    /// Call after new bills are loaded.
    static func checkAndNotify(bills: [Bill]) {
        guard NotificationPreferenceStore.shared.topicConsultations else { return }
        let store = TopicFollowStore.shared
        guard !store.followedIDs.isEmpty else { return }
        for bill in bills {
            for topic in store.matchingFollowedTopics(for: bill.title) {
                schedule(
                    topicName: topic.localizedName,
                    contentTitle: bill.number + ": " + bill.title,
                    source: NSLocalizedString("topic.source.bill", comment: ""),
                    identifier: "topic-\(topic.id)-bill-\(bill.number)"
                )
            }
        }
    }

    // MARK: - Private helpers

    private static func schedule(topicName: String, contentTitle: String, source: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = topicName
        content.subtitle = source
        content.body = contentTitle
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }

    /// Returns a stable, process-launch-independent identifier fragment.
    /// `String.hash` is randomised per-process in Swift; djb2 is deterministic.
    private static func stableID(_ s: String) -> String {
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = hash &* 127 &+ UInt64(byte) }
        return String(hash, radix: 16, uppercase: false)
    }
}
