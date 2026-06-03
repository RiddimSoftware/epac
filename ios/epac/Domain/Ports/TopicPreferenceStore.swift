//
//  TopicPreferenceStore.swift
//  epac
//

import Foundation

@MainActor
protocol TopicPreferenceStore: Sendable {
    func followedTopicIDs() -> Set<String>
    func isFollowing(_ id: String) -> Bool
    func follow(_ id: String)
    func unfollow(_ id: String)
    func toggle(_ id: String)
    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic]
}
