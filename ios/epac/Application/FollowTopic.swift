import Foundation

@MainActor
struct FollowTopic {
    let store: any TopicPreferenceStore

    func execute(topicIDs: some Sequence<String>) {
        let uniqueTopicIDs = Array(Set(topicIDs)).sorted()
        for topicID in uniqueTopicIDs where !topicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.follow(topicID)
        }
    }
}

extension FollowTopic {
    @MainActor
    static func live() -> FollowTopic {
        FollowTopic(
            store: TopicFollowStoreAdapter()
        )
    }
}
