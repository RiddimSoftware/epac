@testable import epac
import Testing

@MainActor
struct FollowTopicTests {
    @Test func persistsUniqueTopicsAndTriggersDeviceRegistrationOnce() {
        let store = TopicFollowingStoreSpy()
        let deviceRegistration = DeviceRegistrationTriggerSpy()
        let useCase = FollowTopic(store: store, deviceRegistration: deviceRegistration)

        useCase.execute(topicIDs: ["healthcare", "housing", "healthcare", "   "])

        #expect(store.persistedTopicIDs == ["healthcare", "housing"])
        #expect(deviceRegistration.triggerCalls == [nil])
    }
}

@MainActor
private final class TopicFollowingStoreSpy: TopicFollowingStore {
    var persistedTopicIDs: [String] = []

    func persistFollowedTopic(_ topicID: String) {
        persistedTopicIDs.append(topicID)
    }
}

private final class DeviceRegistrationTriggerSpy: DeviceRegistrationTriggering {
    var triggerCalls: [String?] = []

    func trigger(myMPMemberID: String?) {
        triggerCalls.append(myMPMemberID)
    }
}
