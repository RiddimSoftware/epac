@testable import epac
import Testing

@MainActor
struct FollowTopicTests {
    @Test func persistsUniqueTopics() {
        let store = TopicPreferenceStoreSpy()
        let useCase = FollowTopic(store: store)

        useCase.execute(topicIDs: ["healthcare", "housing", "healthcare", "   "])

        #expect(store.persistedTopicIDs == ["healthcare", "housing"])
    }
}

@MainActor
private final class TopicPreferenceStoreSpy: TopicPreferenceStore {
    var persistedTopicIDs: [String] = []

    func followedTopicIDs() -> Set<String> {
        Set(persistedTopicIDs)
    }

    func isFollowing(_ id: String) -> Bool {
        persistedTopicIDs.contains(id)
    }

    func follow(_ id: String) {
        persistedTopicIDs.append(id)
    }

    func unfollow(_ id: String) {
        persistedTopicIDs.removeAll { $0 == id }
    }

    func toggle(_ id: String) {
        if isFollowing(id) {
            unfollow(id)
        } else {
            follow(id)
        }
    }

    func matchingFollowedTopics(for title: String) -> [ParliamentaryTopic] {
        ParliamentaryTopic.matching(title).filter { isFollowing($0.id) }
    }

}
