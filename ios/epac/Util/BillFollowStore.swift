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

    /// Call after BillsService.fetchBills() to keep followed-bill state current.
    func updateStoredState(in freshBills: [Bill]) {
        var changed = false
        for bill in freshBills where followedNumbers.contains(bill.number) {
            guard let state = followed[bill.number] else { continue }
            let statusChanged = bill.status.rawValue != state.lastKnownStatus
            let stageChanged = !bill.currentStage.isEmpty && bill.currentStage != state.lastKnownStage
            if statusChanged || stageChanged {
                if statusChanged && bill.status == .royalAssent {
                    Task {
                        let useCase = NotifyFollowedBillRoyalAssent(notificationPort: LiveRoyalAssentNotificationAdapter())
                        try? await useCase.execute(bill: bill)
                    }
                }
                followed[bill.number] = BillFollowState(
                    lastKnownStatus: bill.status.rawValue,
                    lastKnownStage: bill.currentStage,
                    followedAt: state.followedAt
                )
                changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(followed) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
