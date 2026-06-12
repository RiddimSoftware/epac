//
//  NotifyFollowedBillRoyalAssent.swift
//  epac
//

import Foundation

@MainActor
struct NotifyFollowedBillRoyalAssent {
    private let notificationPort: any RoyalAssentNotificationPort

    init(notificationPort: any RoyalAssentNotificationPort) {
        self.notificationPort = notificationPort
    }

    func execute(bill: Bill) async throws {
        let title = bill.number
        let body = String(
            format: NSLocalizedString("notification.royalAssent.body", comment: ""),
            bill.title
        )
        let notification = RoyalAssentNotification(title: title, body: body)
        try await notificationPort.sendNotification(notification)
    }
}
