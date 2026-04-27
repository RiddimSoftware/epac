//
//  BillFollowStore.swift
//  epac
//
//  Persists the set of followed bills and their last-known stage in UserDefaults.
//  Mirrors MemberFollowStore — same pattern, String bill numbers instead of Int member IDs.
//

import Foundation
import Observation

struct BillFollowState: Codable {
    var lastKnownStatus: String  // BillStatus.rawValue
    var lastKnownStage: String   // currentStage string
    var followedAt: Date
}

@MainActor
@Observable
final class BillFollowStore {
    static let shared = BillFollowStore()

    private let key = "epac.followedBills"
    private(set) var followed: [String: BillFollowState] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: BillFollowState].self, from: data) {
            followed = decoded
        }
    }

    func isFollowing(_ number: String) -> Bool { followed[number] != nil }

    func follow(_ bill: Bill) {
        followed[bill.number] = BillFollowState(
            lastKnownStatus: bill.status.rawValue,
            lastKnownStage: bill.currentStage,
            followedAt: Date()
        )
        save()
    }

    func unfollow(_ number: String) {
        followed.removeValue(forKey: number)
        save()
    }

    func toggle(_ bill: Bill) {
        if isFollowing(bill.number) { unfollow(bill.number) } else { follow(bill) }
    }

    var followedNumbers: Set<String> { Set(followed.keys) }

    func unfollowAll() {
        followed.removeAll()
        save()
    }

    /// Call after BillsService.fetchBills() to detect stage or status changes for followed bills.
    /// Returns notification payloads that should be scheduled.
    func detectChanges(in freshBills: [Bill]) -> [BillChangeNotification] {
        var notifications: [BillChangeNotification] = []
        for bill in freshBills where followedNumbers.contains(bill.number) {
            guard let state = followed[bill.number] else { continue }
            let statusChanged = bill.status.rawValue != state.lastKnownStatus
            let stageChanged = !bill.currentStage.isEmpty && bill.currentStage != state.lastKnownStage
            if statusChanged || stageChanged {
                notifications.append(BillChangeNotification(bill: bill, previousStage: state.lastKnownStage))
                // Update stored state
                followed[bill.number] = BillFollowState(
                    lastKnownStatus: bill.status.rawValue,
                    lastKnownStage: bill.currentStage,
                    followedAt: state.followedAt
                )
            }
        }
        if !notifications.isEmpty { save() }
        return notifications
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(followed) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}

struct BillChangeNotification {
    let bill: Bill
    let previousStage: String
}
