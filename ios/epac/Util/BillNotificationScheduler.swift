//
//  BillNotificationScheduler.swift
//  epac
//
//  Schedules local UNUserNotificationCenter notifications for followed bills
//  when stage changes or vote results are detected after BillsView reloads.
//
//  Must be called from MainActor context so BillFollowStore.shared is accessible.
//

import Foundation
import UserNotifications

@MainActor
struct BillNotificationScheduler {

    // MARK: - Stable identifier helpers

    /// Returns a stable, process-launch-independent identifier fragment for a string.
    /// `String.hash` is randomised per-process in Swift; we use a simple djb2 digest
    /// so that `UNNotificationCenter` can deduplicate across launches.
    private static func stableID(_ s: String) -> String {
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = hash &* 127 &+ UInt64(byte) }
        return String(hash, radix: 16, uppercase: false)
    }

    // MARK: - Stage / status change notification

    static func schedule(_ change: BillChangeNotification) {
        let bill = change.bill
        let content = UNMutableNotificationContent()
        content.title = bill.number
        content.sound = .default

        // Stage advance takes priority over general status text
        if !bill.currentStage.isEmpty && bill.currentStage != change.previousStage {
            content.body = String(
                format: NSLocalizedString("bill.notification.stageChange", comment: ""),
                bill.number, bill.currentStage
            )
        }

        // Terminal status overrides stage body
        if bill.status == .royalAssent {
            content.body = String(
                format: NSLocalizedString("bill.notification.royalAssent", comment: ""),
                bill.number
            )
        } else if bill.status == .defeated {
            content.body = String(
                format: NSLocalizedString("bill.notification.defeated", comment: ""),
                bill.number
            )
        }

        guard !content.body.isEmpty else { return }

        if let mpName = PostalCodeViewModel.savedMemberName {
            content.userInfo = ["billNumber": bill.number, "mpLastName": mpName.components(separatedBy: " ").last ?? mpName]
        }

        let request = UNNotificationRequest(
            identifier: "bill-\(bill.number)-\(stableID(bill.currentStage))",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Vote result notification

    /// Schedules a vote-result notification for a followed bill.
    static func scheduleVoteResult(billNumber: String, billTitle: String, yea: Int, nay: Int, mpName: String?, mpVote: String?) {
        let content = UNMutableNotificationContent()
        content.title = billNumber
        content.subtitle = billTitle
        var body = String(
            format: NSLocalizedString("bill.notification.voteResult", comment: ""),
            yea, nay
        )
        if let mpName, let mpVote {
            body += " " + String(
                format: NSLocalizedString("bill.notification.mpVote", comment: ""),
                mpName, mpVote
            )
        }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "bill-vote-\(billNumber)-\(yea)-\(nay)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
