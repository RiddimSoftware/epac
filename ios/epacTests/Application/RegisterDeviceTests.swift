@testable import epac
import Foundation
import Testing

@MainActor
struct RegisterDeviceTests {
    @Test func skipsGatewayWhenPushTokenIsMissing() async {
        let gateway = DeviceRegistrationGatewaySpy()
        let useCase = await makeUseCase(pushToken: nil, gateway: gateway)

        await useCase.execute(myMPMemberID: nil)

        #expect(gateway.requests.isEmpty)
    }

    @Test func buildsRequestFromPortsAndAllowsMyMPOverride() async {
        let gateway = DeviceRegistrationGatewaySpy()
        let useCase = await makeUseCase(pushToken: "token-123", gateway: gateway)

        await useCase.execute(myMPMemberID: "999")

        #expect(gateway.requests == [
            DeviceRegistrationRequest(
                token: "token-123",
                topicIDs: ["economy", "healthcare"],
                billIDs: ["C-12", "C-50"],
                granularity: ["economy": "onlyMyMP", "healthcare": "everyDebate"],
                myMPMemberID: "999"
            )
        ])
    }

    @MainActor
    private func makeUseCase(pushToken: String?, gateway: DeviceRegistrationGatewaySpy) -> RegisterDevice {
        RegisterDevice(
            pushTokenProvider: PushTokenProviderStub(pushToken: pushToken),
            currentMyMPProvider: CurrentMyMPProviderStub(storedMemberID: "1422"),
            topicPreferences: TopicRegistrationPreferencesStub(
                followedTopicIDsForRegistration: ["healthcare", "economy"],
                topicGranularityForRegistration: ["healthcare": "everyDebate", "economy": "onlyMyMP"]
            ),
            billPreferences: BillRegistrationPreferencesStub(
                followedBillIDsForRegistration: ["C-50", "C-12"]
            ),
            gateway: gateway
        )
    }
}

private struct PushTokenProviderStub: PushTokenProviding {
    let pushToken: String?

    func currentPushToken() -> String? {
        pushToken
    }
}

private struct CurrentMyMPProviderStub: CurrentMyMPProviding {
    let storedMemberID: String?

    func currentMyMPMemberID() -> String? {
        storedMemberID
    }
}

@MainActor
private final class TopicRegistrationPreferencesStub: TopicRegistrationPreferencesProviding {
    let followedTopicIDsForRegistration: Set<String>
    let topicGranularityForRegistration: [String: String]

    init(followedTopicIDsForRegistration: Set<String>, topicGranularityForRegistration: [String: String]) {
        self.followedTopicIDsForRegistration = followedTopicIDsForRegistration
        self.topicGranularityForRegistration = topicGranularityForRegistration
    }
}

@MainActor
private final class BillRegistrationPreferencesStub: BillRegistrationPreferencesProviding {
    let followedBillIDsForRegistration: Set<String>

    init(followedBillIDsForRegistration: Set<String>) {
        self.followedBillIDsForRegistration = followedBillIDsForRegistration
    }
}

@MainActor
private final class DeviceRegistrationGatewaySpy: DeviceRegistrationGateway {
    var requests: [DeviceRegistrationRequest] = []

    func register(request: DeviceRegistrationRequest) async throws {
        requests.append(request)
    }
}
