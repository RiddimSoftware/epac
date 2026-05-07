@testable import epac
import Foundation
import Testing

@MainActor
struct ReviewRequestManagerTests {
    @Test func debateThreadTriggerPromptsAfterThirdUniqueThread() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(6, forKey: "epac.review.openCount")
        defaults.set(true, forKey: "epac.review.remoteConfig.enabled")

        var requestCount = 0
        var events: [(String, [String: String])] = []

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            fetchConfigData: { _ in Data() },
            requestReview: {
                requestCount += 1
                return true
            },
            telemetryRecorder: { event, payload in
                events.append((event, payload))
            }
        )

        manager.recordDebateThreadRead(hansardID: "h1", subjectTitle: "Housing")
        manager.recordDebateThreadRead(hansardID: "h2", subjectTitle: "Budget")
        manager.recordDebateThreadRead(hansardID: "h3", subjectTitle: "Climate")

        #expect(requestCount == 1)
        #expect(events.count == 1)
        #expect(events.first?.0 == "review_prompt_shown")
        #expect(events.first?.1["trigger_source"] == "debate_threads_in_session")
    }

    @Test func repeatedFollowedMPProfileViewsPromptOnSecondView() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(6, forKey: "epac.review.openCount")
        defaults.set(true, forKey: "epac.review.remoteConfig.enabled")

        var requestCount = 0
        var payloads: [[String: String]] = []

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            fetchConfigData: { _ in Data() },
            requestReview: {
                requestCount += 1
                return true
            },
            telemetryRecorder: { _, payload in
                payloads.append(payload)
            }
        )

        manager.recordFollowedMemberProfileView(memberID: 42)
        #expect(requestCount == 0)

        manager.recordFollowedMemberProfileView(memberID: 42)
        #expect(requestCount == 1)
        #expect(payloads.last?["trigger_source"] == "followed_mp_profile_repeat_view")
    }

    @Test func remoteConfigFetchEnablesPrompting() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(5, forKey: "epac.review.openCount")

        var requestCount = 0

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            fetchConfigData: { _ in
                Data(#"{"features":{"review_prompt":true}}"#.utf8)
            },
            requestReview: {
                requestCount += 1
                return true
            },
            telemetryRecorder: { _, _ in }
        )

        manager.recordAppOpen()
        // Wait for the unstructured Task spawned by recordAppOpen to finish its async fetch chain.
        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms

        manager.recordFollowedMemberProfileView(memberID: 7)
        manager.recordFollowedMemberProfileView(memberID: 7)

        #expect(requestCount == 1)
    }

    @Test func disabledRemoteConfigBlocksPrompting() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(6, forKey: "epac.review.openCount")
        defaults.set(false, forKey: "epac.review.remoteConfig.enabled")

        var requestCount = 0

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            fetchConfigData: { _ in Data() },
            requestReview: {
                requestCount += 1
                return true
            },
            telemetryRecorder: { _, _ in }
        )

        manager.recordFollowedMemberProfileView(memberID: 99)
        manager.recordFollowedMemberProfileView(memberID: 99)

        #expect(requestCount == 0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReviewRequestManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
