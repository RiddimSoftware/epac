//
//  NotificationManager.swift
//  epac
//

import Foundation
import UserNotifications
import UIKit
import Observation

// Manages push notification permission and incoming notification routing.
//
// Expected APNs payload:
//   {
//     "aps": { "alert": { "title": "New Sitting", "body": "..." } },
//     "date": "2026-04-27T00:00:00Z"   <- ISO8601, used to open the sitting
//   }
//
// Prerequisites (done outside code, in Xcode/App Store Connect):
//   1. Enable Push Notifications capability in Xcode → Signing & Capabilities
//   2. Create an APNs key in App Store Connect → Keys and add to the backend
@MainActor
@Observable
final class NotificationManager: NSObject {
	/// Set when a notification tap or foreground receipt carries a sitting date.
	/// ContentView observes this and navigates to the sitting.
	private(set) var pendingDate: Date?

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

	/// Call from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
	/// Parses the sitting date from the payload and exposes it for navigation.
	func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
		pendingDate = date(from: userInfo)
	}

	func clearPendingDate() {
		pendingDate = nil
	}

	// MARK: - Private

	private func date(from userInfo: [AnyHashable: Any]) -> Date? {
		guard let dateString = userInfo["date"] as? String else { return nil }
		return ISO8601DateFormatter().date(from: dateString)
	}
}

extension NotificationManager: UNUserNotificationCenterDelegate {
	// Foreground: display banner AND route the sitting date for navigation.
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		// Extract String (Sendable) before crossing actor boundary.
		let dateString = notification.request.content.userInfo["date"] as? String
		Task { @MainActor [weak self] in
			self?.pendingDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
		}
		completionHandler([.banner, .sound, .badge])
	}

	// Background/terminated: process the tap.
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let dateString = response.notification.request.content.userInfo["date"] as? String
		Task { @MainActor [weak self] in
			self?.pendingDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
		}
		completionHandler()
	}
}
