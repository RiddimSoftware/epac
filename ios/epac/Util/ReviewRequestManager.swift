//
//  ReviewRequestManager.swift
//  epac
//
//  Remote-config-gated in-app review prompting. Prompts only at earned moments:
//  - after the user reads several debate threads in one app session
//  - after the user views a followed MP's profile multiple times
//

import Foundation
import Sentry
import StoreKit
import UIKit

struct ReviewPromptRemoteConfig: Equatable {
    var isEnabled: Bool = false
}

private struct AppConfigResponse: Decodable {
    let features: [String: Bool]
}

@MainActor
final class ReviewRequestManager {
    @MainActor static let shared = ReviewRequestManager()

    private enum TriggerSource: String {
        case debateThreadsInSession = "debate_threads_in_session"
        case followedMPProfileRepeatView = "followed_mp_profile_repeat_view"
    }

    private let installDateKey = "epac.review.installDate"
    private let openCountKey = "epac.review.openCount"
    private let lastPromptKey = "epac.review.lastPromptDate"
    private let sessionNumberKey = "epac.review.sessionNumber"
    private let sessionThreadsKey = "epac.review.sessionThreads"
    private let memberProfileViewsKey = "epac.review.memberProfileViews"
    private let remoteConfigEnabledKey = "epac.review.remoteConfig.enabled"
    private let remoteConfigFetchedAtKey = "epac.review.remoteConfig.fetchedAt"

    private let minDaysInstalled = 7
    private let minOpenCount = 5
    private let minDaysSincePrompt = 90
    private let minDebateThreadsPerSession = 3
    private let minFollowedMPProfileViews = 2
    private let remoteConfigTTL: TimeInterval = 60 * 60 * 12

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetchConfigData: @Sendable (URL) async throws -> Data
    private let requestReview: () -> Bool
    private let telemetryRecorder: (String, [String: String]) -> Void

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetchConfigData: @escaping @Sendable (URL) async throws -> Data = { url in
            let (data, _) = try await NetworkService.shared.data(from: url)
            return data
        },
        requestReview: @escaping () -> Bool = {
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                return false
            }
            SKStoreReviewController.requestReview(in: scene)
            return true
        },
        telemetryRecorder: @escaping (String, [String: String]) -> Void = ReviewRequestManager.defaultTelemetryRecorder
    ) {
        self.defaults = defaults
        self.now = now
        self.fetchConfigData = fetchConfigData
        self.requestReview = requestReview
        self.telemetryRecorder = telemetryRecorder
    }

    func recordAppOpen() {
        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(now(), forKey: installDateKey)
        }

        defaults.set(defaults.integer(forKey: openCountKey) + 1, forKey: openCountKey)
        defaults.set(defaults.integer(forKey: sessionNumberKey) + 1, forKey: sessionNumberKey)
        defaults.set([], forKey: sessionThreadsKey)

        Task { await refreshRemoteConfigIfNeeded() }
    }

    func recordDebateThreadRead(hansardID: String, subjectTitle: String) {
        let threadID = "\(hansardID)::\(subjectTitle.trimmingCharacters(in: .whitespacesAndNewlines))"
        var threadIDs = Set(defaults.stringArray(forKey: sessionThreadsKey) ?? [])
        let inserted = threadIDs.insert(threadID).inserted
        defaults.set(Array(threadIDs).sorted(), forKey: sessionThreadsKey)

        guard inserted, threadIDs.count >= minDebateThreadsPerSession else { return }
        requestReviewIfEligible(trigger: .debateThreadsInSession)
    }

    func recordFollowedMemberProfileView(memberID: Int) {
        var viewCounts = defaults.dictionary(forKey: memberProfileViewsKey) as? [String: Int] ?? [:]
        let key = String(memberID)
        viewCounts[key] = (viewCounts[key] ?? 0) + 1
        defaults.set(viewCounts, forKey: memberProfileViewsKey)

        guard (viewCounts[key] ?? 0) >= minFollowedMPProfileViews else { return }
        requestReviewIfEligible(trigger: .followedMPProfileRepeatView)
    }

    private func requestReviewIfEligible(trigger: TriggerSource) {
        guard remoteConfig().isEnabled else { return }
        guard meetsGateCriteria() else { return }
        guard requestReview() else { return }
        defaults.set(now(), forKey: lastPromptKey)
        telemetryRecorder(
            "review_prompt_shown",
            [
                "trigger_source": trigger.rawValue,
                "open_count": String(defaults.integer(forKey: openCountKey)),
                "session_number": String(defaults.integer(forKey: sessionNumberKey))
            ]
        )
    }

    private func meetsGateCriteria() -> Bool {
        guard let installDate = defaults.object(forKey: installDateKey) as? Date,
              now().timeIntervalSince(installDate) >= Double(minDaysInstalled * 86_400) else {
            return false
        }

        guard defaults.integer(forKey: openCountKey) >= minOpenCount else {
            return false
        }

        if let lastPrompt = defaults.object(forKey: lastPromptKey) as? Date,
           now().timeIntervalSince(lastPrompt) < Double(minDaysSincePrompt * 86_400) {
            return false
        }

        return true
    }

    private func remoteConfig() -> ReviewPromptRemoteConfig {
        ReviewPromptRemoteConfig(
            isEnabled: defaults.bool(forKey: remoteConfigEnabledKey)
        )
    }

    private func refreshRemoteConfigIfNeeded() async {
        if let fetchedAt = defaults.object(forKey: remoteConfigFetchedAtKey) as? Date,
           now().timeIntervalSince(fetchedAt) < remoteConfigTTL {
            return
        }

        let url = BackendConfig.shared.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("config")

        do {
            let data = try await fetchConfigData(url)
            let response = try JSONDecoder().decode(AppConfigResponse.self, from: data)
            defaults.set(response.features["review_prompt"] ?? false, forKey: remoteConfigEnabledKey)
            defaults.set(now(), forKey: remoteConfigFetchedAtKey)
        } catch {
            Log.warning("review.remoteConfig.fetchFailed error=\(error.localizedDescription)")
        }
    }

    private nonisolated static func defaultTelemetryRecorder(_ event: String, _ payload: [String: String]) {
        Log.warning("\(event) trigger=\(payload["trigger_source"] ?? "unknown")")

        SentrySDK.configureScope { scope in
            scope.setTag(value: event, key: "event")
            payload.forEach { key, value in
                scope.setTag(value: value, key: key)
            }
        }
        SentrySDK.capture(message: event)
    }
}
