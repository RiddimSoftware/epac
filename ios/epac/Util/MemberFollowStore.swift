//
//  MemberFollowStore.swift
//  epac
//
//  Persists the set of followed MPs in UserDefaults.
//

import Foundation
import Observation

struct FollowPreferences: Codable {}

@MainActor
@Observable
final class MemberFollowStore {
    static let shared = MemberFollowStore()

    private let prefsKey = "epac.followedMembers"
    private(set) var followed: [Int: FollowPreferences] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: prefsKey),
           let decoded = try? JSONDecoder().decode([Int: FollowPreferences].self, from: data) {
            followed = decoded
        }
    }

    func isFollowing(_ memberID: Int) -> Bool { followed[memberID] != nil }

    func follow(_ memberID: Int) {
        followed[memberID] = FollowPreferences()
        save()
    }

    func unfollow(_ memberID: Int) {
        followed.removeValue(forKey: memberID)
        save()
    }

    func toggle(_ memberID: Int) {
        if isFollowing(memberID) { unfollow(memberID) } else { follow(memberID) }
    }

    var followedIDs: Set<Int> { Set(followed.keys) }

    private func save() {
        if let encoded = try? JSONEncoder().encode(followed) {
            UserDefaults.standard.set(encoded, forKey: prefsKey)
        }
    }
}
