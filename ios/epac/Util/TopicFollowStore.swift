//
//  TopicFollowStore.swift
//  epac
//
//  Persists the set of followed Parliamentary topic IDs in UserDefaults.
//  Mirrors BillFollowStore / MemberFollowStore — same singleton pattern.
//

import Foundation
import Observation

@MainActor
@Observable
final class TopicFollowStore {
    static let shared = TopicFollowStore()
    private let key = "epac.followedTopics"
    private(set) var followedIDs: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            followedIDs = decoded
        }
    }

    func isFollowing(_ id: String) -> Bool { followedIDs.contains(id) }
    func follow(_ id: String) { followedIDs.insert(id); save() }
    func unfollow(_ id: String) { followedIDs.remove(id); save() }
    func toggle(_ id: String) { isFollowing(id) ? unfollow(id) : follow(id) }

    /// Returns followed topics whose keywords match the given content title.
    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic] {
        ParliamentaryTopic.matching(title).filter { isFollowing($0.id) }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(followedIDs) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
