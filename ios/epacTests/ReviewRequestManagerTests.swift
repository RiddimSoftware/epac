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

        var requestCount = 0
        var events: [(String, [String: String])] = []

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
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

        var requestCount = 0
        var payloads: [[String: String]] = []

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
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

    @Test func defaultRecorderUsesInjectedTelemetryProvider() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(6, forKey: "epac.review.openCount")
        let telemetry = RecordingTelemetryProvider()

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            requestReview: { true },
            telemetry: telemetry
        )

        manager.recordFollowedMemberProfileView(memberID: 42)
        manager.recordFollowedMemberProfileView(memberID: 42)

        #expect(telemetry.store.events.count == 1)
        #expect(telemetry.store.events.first?.0 == "review_prompt_shown")
        #expect(telemetry.store.events.first?.1["event"] == "review_prompt_shown")
        #expect(telemetry.store.events.first?.1["trigger_source"] == "followed_mp_profile_repeat_view")
    }

    @Test func appOpenUpdatesLocalSessionState() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
            requestReview: { true },
            telemetryRecorder: { _, _ in }
        )

        manager.recordAppOpen()

        #expect(defaults.integer(forKey: "epac.review.openCount") == 1)
        #expect(defaults.integer(forKey: "epac.review.sessionNumber") == 1)
        #expect(defaults.stringArray(forKey: "epac.review.sessionThreads") == [])
        #expect(defaults.dictionary(forKey: "epac.review.memberProfileViews") == nil)
    }

    @Test func recentPromptStillBlocksLocalPrompting() async throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-8 * 86_400), forKey: "epac.review.installDate")
        defaults.set(6, forKey: "epac.review.openCount")
        defaults.set(now.addingTimeInterval(-30 * 86_400), forKey: "epac.review.lastPromptDate")

        var requestCount = 0

        let manager = ReviewRequestManager(
            defaults: defaults,
            now: { now },
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
