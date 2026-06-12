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
    var hasUnreadUpdate: Bool?   // status changed since last viewed
}

@MainActor
@Observable
final class BillFollowStore {
    static let shared = BillFollowStore()

    private let key = "epac.followedBills"
    private let orderKey = "epac.followedBills.order"
    private(set) var followed: [String: BillFollowState] = [:]
    private(set) var orderedBillNumbers: [String] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: BillFollowState].self, from: data) {
            followed = decoded
        }
        if let order = UserDefaults.standard.stringArray(forKey: orderKey) {
            orderedBillNumbers = order.filter { followed[$0] != nil }
            for billNum in followed.keys {
                if !orderedBillNumbers.contains(billNum) {
                    orderedBillNumbers.append(billNum)
                }
            }
        } else {
            orderedBillNumbers = followed.sorted { $0.value.followedAt > $1.value.followedAt }.map { $0.key }
            saveOrder()
        }
    }

    func isFollowing(_ number: String) -> Bool { followed[number] != nil }

    func follow(_ bill: Bill) {
        followed[bill.number] = BillFollowState(
            lastKnownStatus: bill.status.rawValue,
            lastKnownStage: bill.currentStage,
            followedAt: Date(),
            hasUnreadUpdate: false
        )
        if !orderedBillNumbers.contains(bill.number) {
            orderedBillNumbers.insert(bill.number, at: 0)
            saveOrder()
        }
        save()
    }

    func unfollow(_ number: String) {
        followed.removeValue(forKey: number)
        orderedBillNumbers.removeAll { $0 == number }
        saveOrder()
        save()
    }

    func toggle(_ bill: Bill) {
        if isFollowing(bill.number) { unfollow(bill.number) } else { follow(bill) }
    }

    var followedNumbers: Set<String> { Set(followed.keys) }

    func unfollowAll() {
        followed.removeAll()
        orderedBillNumbers.removeAll()
        saveOrder()
        save()
    }

    func markAsRead(_ number: String) {
        guard var state = followed[number] else { return }
        if state.hasUnreadUpdate == true {
            state.hasUnreadUpdate = false
            followed[number] = state
            save()
        }
    }

    func moveFollowedBills(from source: IndexSet, to destination: Int) {
        orderedBillNumbers.move(fromOffsets: source, toOffset: destination)
        saveOrder()
    }

    /// Call after BillsService.fetchBills() to keep followed-bill state current.
    func updateStoredState(in freshBills: [Bill]) {
        var changed = false
        for bill in freshBills where followedNumbers.contains(bill.number) {
            guard let state = followed[bill.number] else { continue }
            let statusChanged = bill.status.rawValue != state.lastKnownStatus
            let stageChanged = !bill.currentStage.isEmpty && bill.currentStage != state.lastKnownStage
            if statusChanged || stageChanged {
                followed[bill.number] = BillFollowState(
                    lastKnownStatus: bill.status.rawValue,
                    lastKnownStage: bill.currentStage,
                    followedAt: state.followedAt,
                    hasUnreadUpdate: statusChanged || (state.hasUnreadUpdate ?? false)
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

    private func saveOrder() {
        UserDefaults.standard.set(orderedBillNumbers, forKey: orderKey)
    }
}

