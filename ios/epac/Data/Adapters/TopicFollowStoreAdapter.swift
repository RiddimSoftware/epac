//
//  TopicFollowStoreAdapter.swift
//  epac
//

import Foundation

@MainActor
final class TopicFollowStoreAdapter: TopicPreferenceStore, @unchecked Sendable {
    private let store: TopicFollowStore

    init(store: TopicFollowStore = TopicFollowStore.shared) {
        self.store = store
    }

    func followedTopicIDs() -> Set<String> {
        store.followedIDs
    }

    func isFollowing(_ id: String) -> Bool {
        store.isFollowing(id)
    }

    func follow(_ id: String) {
        store.follow(id)
    }

    func unfollow(_ id: String) {
        store.unfollow(id)
    }

    func toggle(_ id: String) {
        store.toggle(id)
    }

    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic] {
        store.matchingFollowedTopics(for: title)
    }
}
