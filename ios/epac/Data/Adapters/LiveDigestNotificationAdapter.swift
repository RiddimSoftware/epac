//
//  LiveDigestNotificationAdapter.swift
//  epac
//
//  Formats a DailyDigest into a local notification using UNUserNotificationCenter.
//  Format spec (EPAC-917):
//    Title:  "Parliament sat today · <Date>"
//    Body:   "<N> debates · <M>% of MPs present · <Subject 1>, <Subject 2>, <Subject 3>"
//            "1 recorded vote: <Bill name> <passed|defeated> <Y>–<N>"   (only if vote != nil)
//  All facts come from the authoritative DailyDigest value; no generated text.
//
//  userInfo carries the sitting date (ISO-8601) and a notification kind so the
//  AppDelegate's UNUserNotificationCenter delegate can route a tap to the
//  corresponding Hansard sitting in the Debates calendar.
//

import Foundation
import UserNotifications

/// Constants used by both the notification adapter and the UNUserNotificationCenter
/// delegate that handles taps. Defined outside the `@MainActor` struct so the
/// delegate (nonisolated) can read them without crossing actor boundaries.
enum DailyDigestNotificationPayload {
    static let categoryIdentifier = "epac.notifications.dailyDigest"
    static let userInfoKindKey = "epac.notification.kind"
    static let userInfoDateKey = "epac.notification.date"
    static let userInfoKindValue = "dailyDigest"
}

@MainActor
struct LiveDigestNotificationAdapter: DigestNotificationPort {
    private static let immediateTriggerDelay: TimeInterval = 1

    private static let userInfoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    func send(_ digest: DailyDigest) async throws {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let content = UNMutableNotificationContent()
        content.title = DailyDigestFormatter.title(for: digest.date)
        content.body = DailyDigestFormatter.body(for: digest)
        content.sound = .default
        content.categoryIdentifier = DailyDigestNotificationPayload.categoryIdentifier
        content.userInfo = [
            DailyDigestNotificationPayload.userInfoKindKey: DailyDigestNotificationPayload.userInfoKindValue,
            DailyDigestNotificationPayload.userInfoDateKey: Self.userInfoDateFormatter.string(from: digest.date)
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.immediateTriggerDelay,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}
