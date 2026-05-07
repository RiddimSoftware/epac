import Foundation

@MainActor
protocol TopicFollowingStore: AnyObject {
    func persistFollowedTopic(_ topicID: String)
}

@MainActor
struct FollowTopic {
    let store: any TopicFollowingStore
    let deviceRegistration: any DeviceRegistrationTriggering

    func execute(topicIDs: some Sequence<String>) {
        let uniqueTopicIDs = Array(Set(topicIDs)).sorted()
        for topicID in uniqueTopicIDs where !topicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.persistFollowedTopic(topicID)
        }
        deviceRegistration.trigger(myMPMemberID: nil)
    }
}

extension FollowTopic {
    @MainActor
    static func live() -> FollowTopic {
        FollowTopic(
            store: TopicFollowStore.shared,
            deviceRegistration: TriggerDeviceRegistration.live()
        )
    }
}
