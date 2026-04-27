//
//  NotificationManager.swift
//  epac
//

import Foundation
import UserNotifications
import UIKit
import Observation

// Manages APNs registration, token storage, and notification routing.
//
// Supported payload keys:
//   "date"         ISO8601 date string — opens that sitting
//   "hansard_date" ISO8601 date string — alias used by topic-notifier
//   "topic_id"     ParliamentaryTopic slug — set when notification is topic-driven
//
// Prerequisites (one-time, outside code):
//   1. Enable Push Notifications capability in Xcode → Signing & Capabilities
//   2. Create an APNs key in App Store Connect → Keys and add to the backend
@MainActor
@Observable
final class NotificationManager: NSObject {
    /// Set when a notification tap or foreground receipt carries a sitting date.
    /// ContentView observes this and navigates to the sitting.
    private(set) var pendingDate: Date?

    /// Topic ID from a topic-debate notification, cleared after navigation.
    private(set) var pendingTopicId: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests authorization and registers for remote notifications.
    /// Safe to call multiple times — the system returns the existing status.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
            Log.debug("Notification authorization: \(granted)")
        } catch {
            Log.debug("Notification auth error: \(error.localizedDescription)")
        }
    }

    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Persists the token and re-registers topic subscriptions with the backend.
    func didRegisterToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "epac.apnsToken")
        Log.debug("APNs token registered: \(token.prefix(12))...")
        Task {
            await TopicFollowStore.shared.registerDevice()
        }
    }

    /// Call from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        let (date, topicId) = parse(userInfo)
        pendingDate = date
        pendingTopicId = topicId
    }

    func clearPendingDate() {
        pendingDate = nil
        pendingTopicId = nil
    }

    // MARK: - Private

    private func parse(_ userInfo: [AnyHashable: Any]) -> (Date?, String?) {
        let topicId = userInfo["topic_id"] as? String
        // Accept either "date" or "hansard_date" keys.
        let dateString = (userInfo["hansard_date"] as? String) ?? (userInfo["date"] as? String)
        let date = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
        return (date, topicId)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Foreground: display banner AND route date+topic for navigation.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let topicId = userInfo["topic_id"] as? String
        let dateString = (userInfo["hansard_date"] as? String) ?? (userInfo["date"] as? String)
        Task { @MainActor [weak self] in
            self?.pendingDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
            self?.pendingTopicId = topicId
        }
        completionHandler([.banner, .sound, .badge])
    }

    // Background/terminated: process the tap.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let topicId = userInfo["topic_id"] as? String
        let dateString = (userInfo["hansard_date"] as? String) ?? (userInfo["date"] as? String)
        Task { @MainActor [weak self] in
            self?.pendingDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
            self?.pendingTopicId = topicId
        }
        completionHandler()
    }
}
