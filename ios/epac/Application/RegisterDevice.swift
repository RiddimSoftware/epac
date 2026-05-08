import Foundation

struct DeviceRegistrationRequest: Equatable, Sendable {
    let token: String
    let topicIDs: [String]
    let billIDs: [String]
    let granularity: [String: String]
    let myMPMemberID: String?
}

protocol PushTokenProviding {
    func currentPushToken() -> String?
}

protocol CurrentMyMPProviding {
    func currentMyMPMemberID() -> String?
}

@MainActor
protocol TopicRegistrationPreferencesProviding: AnyObject {
    var followedTopicIDsForRegistration: Set<String> { get }
    var topicGranularityForRegistration: [String: String] { get }
}

@MainActor
protocol BillRegistrationPreferencesProviding: AnyObject {
    var followedBillIDsForRegistration: Set<String> { get }
}

@MainActor
protocol DeviceRegistrationGateway {
    func register(request: DeviceRegistrationRequest) async throws
}

@MainActor
protocol RegisterDeviceUseCase {
    func execute(myMPMemberID: String?) async
}

@MainActor
protocol DeviceRegistrationTriggering {
    func trigger(myMPMemberID: String?)
}

@MainActor
struct RegisterDevice: RegisterDeviceUseCase {
    let pushTokenProvider: any PushTokenProviding
    let currentMyMPProvider: any CurrentMyMPProviding
    let topicPreferences: any TopicRegistrationPreferencesProviding
    let billPreferences: any BillRegistrationPreferencesProviding
    let gateway: any DeviceRegistrationGateway

    func execute(myMPMemberID: String? = nil) async {
        guard let token = pushTokenProvider.currentPushToken(), !token.isEmpty else { return }

        let request = await MainActor.run {
            DeviceRegistrationRequest(
                token: token,
                topicIDs: Array(topicPreferences.followedTopicIDsForRegistration).sorted(),
                billIDs: Array(billPreferences.followedBillIDsForRegistration).sorted(),
                granularity: topicPreferences.topicGranularityForRegistration,
                myMPMemberID: myMPMemberID ?? currentMyMPProvider.currentMyMPMemberID()
            )
        }

        try? await gateway.register(request: request)
    }
}

@MainActor
struct TriggerDeviceRegistration: DeviceRegistrationTriggering {
    let registerDevice: any RegisterDeviceUseCase

    func trigger(myMPMemberID: String? = nil) {
        Task { @MainActor in
            await registerDevice.execute(myMPMemberID: myMPMemberID)
        }
    }
}

struct UserDefaultsPushTokenProvider: PushTokenProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentPushToken() -> String? {
        defaults.string(forKey: "epac.apnsToken")
    }
}

struct UserDefaultsCurrentMyMPProvider: CurrentMyMPProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentMyMPMemberID() -> String? {
        defaults.string(forKey: "epac.myMPMemberID")
    }
}

@MainActor
struct BackendDeviceRegistrationGateway: DeviceRegistrationGateway {
    private let networkService: NetworkService
    private let url: URL

    init(
        networkService: NetworkService = .shared,
        url: URL = BackendConfig.shared.baseURL.appendingPathComponent("device/register")
    ) {
        self.networkService = networkService
        self.url = url
    }

    func register(request: DeviceRegistrationRequest) async throws {
        let body: [String: Any] = [
            "token": request.token,
            "topic_ids": request.topicIDs,
            "bill_ids": request.billIDs,
            "granularity": request.granularity,
            "my_mp_member_id": request.myMPMemberID as Any
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = data
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await networkService.data(for: urlRequest)
    }
}

extension RegisterDevice {
    @MainActor
    static func live() -> RegisterDevice {
        RegisterDevice(
            pushTokenProvider: UserDefaultsPushTokenProvider(),
            currentMyMPProvider: UserDefaultsCurrentMyMPProvider(),
            topicPreferences: TopicFollowStore.shared,
            billPreferences: BillFollowStore.shared,
            gateway: BackendDeviceRegistrationGateway()
        )
    }
}

extension TriggerDeviceRegistration {
    @MainActor
    static func live() -> TriggerDeviceRegistration {
        TriggerDeviceRegistration(registerDevice: RegisterDevice.live())
    }
}
