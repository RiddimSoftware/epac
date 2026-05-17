@testable import epac
import Testing

@MainActor
struct FollowTopicTests {
    @Test func persistsUniqueTopics() {
        let store = TopicFollowingStoreSpy()
        let useCase = FollowTopic(store: store)

        useCase.execute(topicIDs: ["healthcare", "housing", "healthcare", "   "])

        #expect(store.persistedTopicIDs == ["healthcare", "housing"])
    }
}

@MainActor
private final class TopicFollowingStoreSpy: TopicFollowingStore {
    var persistedTopicIDs: [String] = []

    func persistFollowedTopic(_ topicID: String) {
        persistedTopicIDs.append(topicID)
    }
}
