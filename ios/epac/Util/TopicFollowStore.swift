//
//  TopicFollowStore.swift
//  epac
//
//  Persists followed Parliamentary topic IDs and per-topic notification
//  granularity in UserDefaults.

import Foundation
import Observation

// Granularity of push notifications for a followed topic.
enum TopicNotificationGranularity: String, Codable, CaseIterable {
    case everyDebate    // notify whenever this topic is debated (default)
    case onlyMyMP       // notify only when the user's MP speaks on this topic
    case off            // no push for this topic
}

@MainActor
@Observable
final class TopicFollowStore {
    static let shared = TopicFollowStore()

    private let key = "epac.followedTopics"
    private let granularityKey = "epac.topicGranularity"

    private(set) var followedIDs: Set<String> = []
    private(set) var granularity: [String: TopicNotificationGranularity] = [:]

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            followedIDs = decoded
        }
        if let data = d.data(forKey: granularityKey),
           let decoded = try? JSONDecoder().decode([String: TopicNotificationGranularity].self, from: data) {
            granularity = decoded
        }
    }

    // MARK: - Topic following

    func isFollowing(_ id: String) -> Bool { followedIDs.contains(id) }

    func follow(_ id: String) {
        persistFollowedTopic(id)
        TriggerDeviceRegistration.live().trigger(myMPMemberID: nil)
    }

    func unfollow(_ id: String) {
        persistUnfollowedTopic(id)
        TriggerDeviceRegistration.live().trigger(myMPMemberID: nil)
    }

    func toggle(_ id: String) { isFollowing(id) ? unfollow(id) : follow(id) }

    // MARK: - Granularity

    func granularity(for id: String) -> TopicNotificationGranularity {
        granularity[id] ?? .everyDebate
    }

    func setGranularity(_ value: TopicNotificationGranularity, for id: String) {
        persistGranularity(value, for: id)
        TriggerDeviceRegistration.live().trigger(myMPMemberID: nil)
    }

    // MARK: - Topic matching

    /// Returns followed topics whose keywords match the given content title.
    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic] {
        ParliamentaryTopic.matching(title).filter { isFollowing($0.id) }
    }

    // MARK: - Device registration

    /// Registers the current APNs token + topic preferences with the backend.
    /// Call on app launch after the token is received, and whenever preferences change.
    func registerDevice(myMPMemberID: String? = nil) async {
        await RegisterDevice.live().execute(myMPMemberID: myMPMemberID)
    }

    // MARK: - Persistence helpers

    func persistFollowedTopic(_ id: String) {
        followedIDs.insert(id)
        if granularity[id] == nil { granularity[id] = .everyDebate }
        save()
    }

    func persistUnfollowedTopic(_ id: String) {
        followedIDs.remove(id)
        granularity.removeValue(forKey: id)
        save()
    }

    func persistGranularity(_ value: TopicNotificationGranularity, for id: String) {
        granularity[id] = value
        save()
    }

    // MARK: - Private

    private func save() {
        let d = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(followedIDs) {
            d.set(encoded, forKey: key)
        }
        if let encoded = try? JSONEncoder().encode(granularity) {
            d.set(encoded, forKey: granularityKey)
        }
    }
}

extension TopicFollowStore: TopicFollowingStore, TopicRegistrationPreferencesProviding {
    var followedTopicIDsForRegistration: Set<String> { followedIDs }

    var topicGranularityForRegistration: [String: String] {
        Dictionary(uniqueKeysWithValues: granularity.map { ($0.key, $0.value.rawValue) })
    }
}
