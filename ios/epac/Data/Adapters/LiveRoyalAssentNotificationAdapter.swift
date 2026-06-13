//
//  LiveRoyalAssentNotificationAdapter.swift
//  epac
//

import Foundation
import UserNotifications

struct LiveRoyalAssentNotificationAdapter: RoyalAssentNotificationPort {
    func sendNotification(_ notification: RoyalAssentNotification) async throws {
        let center = UNUserNotificationCenter.current()

        // Check authorization first; request it if not determined yet.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        // Fire the local notification almost immediately (1 second delay).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }
}
