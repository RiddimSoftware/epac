//
//  TopicFollowStore.swift
//  epac
//
//  Persists followed Parliamentary topic IDs in UserDefaults.

import Foundation
import Observation

@MainActor
@Observable
final class TopicFollowStore {
    static let shared = TopicFollowStore()

    private let key = "epac.followedTopics"

    private(set) var followedIDs: Set<String> = []

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            followedIDs = decoded
        }
    }

    // MARK: - Topic following

    func isFollowing(_ id: String) -> Bool { followedIDs.contains(id) }

    func follow(_ id: String) {
        persistFollowedTopic(id)
    }

    func unfollow(_ id: String) {
        persistUnfollowedTopic(id)
    }

    func toggle(_ id: String) { isFollowing(id) ? unfollow(id) : follow(id) }

    // MARK: - Topic matching

    /// Returns followed topics whose keywords match the given content title.
    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic] {
        ParliamentaryTopic.matching(title).filter { isFollowing($0.id) }
    }

    // MARK: - Persistence helpers

    func persistFollowedTopic(_ id: String) {
        followedIDs.insert(id)
        save()
    }

    func persistUnfollowedTopic(_ id: String) {
        followedIDs.remove(id)
        save()
    }

    // MARK: - Private

    private func save() {
        let d = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(followedIDs) {
            d.set(encoded, forKey: key)
        }
    }
}
