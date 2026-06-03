//
//  FreshInstallPerfTests.swift
//  epacUITests
//
//  EPAC-2205: fresh-install, live-network "realistic" performance suite.
//
//  Archetype: a true fresh install (`-UI_TEST_FRESH_STATE`, no evidence seed) that
//  walks the real onboarding flow and then makes LIVE backend calls when opening a
//  debate. It extends the deterministic golden-path CUJ (EPAC-2143,
//  OnboardingAndFirstDebateUITests) with live network plus perf instrumentation.
//
//  This suite is intentionally NOT a PR gate. Real-backend latency is non-deterministic,
//  so it runs only in the nightly / device context and reports network failures as a
//  soft `XCTSkip` rather than a hard red — transient backend issues are a trend signal,
//  not a merge blocker.
//
//  How it stays off the PR gate (two independent guards):
//    1. No PR workflow runs the `epacUITests` target — `pr-build.yml` only builds. The
//       golden-path CUJ workflow pins `-only-testing:.../OnboardingAndFirstDebateUITests`,
//       so this class is never pulled in there either.
//    2. Belt-and-suspenders: every test here skips unless `EPAC_PERF_NIGHTLY=1` is present
//       in the process environment. Only the nightly/device runner sets it (wired by the
//       device-nightly schedule, issue 8). Absent it, the suite skips cleanly and makes no
//       live network calls.
//
//  Measurements:
//    * Cold launch — `XCTApplicationLaunchMetric` over a fresh-install launch.
//    * Onboarding traversal time — wall-clock duration + an `os_signpost` interval.
//    * Debate-load latency — `XCTClockMetric` + an `os_signpost` interval around the real
//      `fetchTranscript`, over the navigate→loaded window.
//
//  Caveat: under XCTest the SwiftData store is in-memory, so this *simulates* a fresh
//  install — it exercises onboarding + the live fetch, but NOT the on-disk first-run /
//  migration path. Network calls hit production (Release); keep them read-only.
//
//  See docs/perf/realistic-fresh-install-suite.md.
//

import OSLog
import XCTest

final class FreshInstallPerfTests: XCTestCase {
	// Launch arguments (mirror OnboardingAndFirstDebateUITests).
	private static let freshStateArgument = "-UI_TEST_FRESH_STATE"
	private static let enabledLaunchValue = "1"

	// Nightly/device opt-in gate. Only the nightly/device runner sets this; absent it, skip.
	private static let nightlyGateEnvKey = "EPAC_PERF_NIGHTLY"
	private static let nightlyGateEnabledValue = "1"

	// Accessibility identifiers / labels (mirror OnboardingAndFirstDebateUITests).
	private static let parliamentTabLabel = "Parliament"
	private static let sittingDayIdentifier = "sitting-day-cell"
	private static let debateContentIdentifier = "debate-content"
	private static let onboardingButtonLabels = ["Skip", "Continue", "Next", "Done", "Get Started"]

	// Tuning. Live-network timeouts are generous because real-backend latency varies.
	private static let maxOnboardingDismissalTaps = 10
	private static let onboardingDismissalDelaySeconds: UInt32 = 1
	private static let parliamentTabTimeout: TimeInterval = 20
	private static let sittingDayTimeout: TimeInterval = 30
	private static let debateContentTimeout: TimeInterval = 45
	private static let cellTapOffset = 0.5

	// os_signpost intervals — visible to the device-nightly Instruments/MetricKit context.
	private static let signpostSubsystem = "com.riddimsoftware.epac.perf"
	private static let signpostCategory = "FreshInstallPerf"
	private static let onboardingSignpostName: StaticString = "onboardingTraversal"
	private static let fetchTranscriptSignpostName: StaticString = "fetchTranscript"

	private let signposter = OSSignposter(
		subsystem: FreshInstallPerfTests.signpostSubsystem,
		category: FreshInstallPerfTests.signpostCategory
	)
	private var app = XCUIApplication()

	override func setUpWithError() throws {
		try skipUnlessNightlyContext()
		continueAfterFailure = false
		app = XCUIApplication()
		app.launchArguments += [Self.freshStateArgument, Self.enabledLaunchValue]
	}

	override func tearDownWithError() throws {
		app.terminate()
	}

	// MARK: - Cold launch

	/// AC: cold launch is measured via `XCTApplicationLaunchMetric`, on a fresh install.
	@MainActor
	func test_coldLaunch_freshInstall_perf() throws {
		measure(metrics: [XCTApplicationLaunchMetric()]) {
			app.launch()
		}
	}

	// MARK: - Onboarding traversal + live debate load

	/// AC: fresh install → complete onboarding (incl. the postal-code setup step) →
	/// navigate to a debate → trigger a real `fetchTranscript`, capturing onboarding
	/// traversal time and debate-load latency. Fails soft on live-network errors.
	@MainActor
	func test_freshInstall_onboarding_liveDebateLoad_perf() throws {
		app.launch()

		// Onboarding traversal (welcome → postal code → MP confirm → topics). Traversed via
		// the per-step "Skip" affordance, the same path the golden-path CUJ validates.
		let parliamentTab = app.tabBars.buttons[Self.parliamentTabLabel]
		let onboardingState = signposter.beginInterval(Self.onboardingSignpostName)
		let onboardingStart = Date()
		dismissAllOnboardingScreens(in: app)
		XCTAssertTrue(
			parliamentTab.waitForExistence(timeout: Self.parliamentTabTimeout),
			"Parliament tab should appear after completing onboarding"
		)
		let onboardingDuration = Date().timeIntervalSince(onboardingStart)
		signposter.endInterval(Self.onboardingSignpostName, onboardingState)
		attachDuration(onboardingDuration, named: "onboarding-traversal-seconds")

		parliamentTab.tap()

		// The sitting calendar load is itself a live call (no seed, in-memory store). If it
		// never yields a sitting day, treat it as a transient backend issue and skip.
		let sittingDayCell = app.descendants(matching: .any)
			.matching(identifier: Self.sittingDayIdentifier).firstMatch
		try XCTSkipUnless(
			sittingDayCell.waitForExistence(timeout: Self.sittingDayTimeout),
			"No sitting day loaded over the live network within \(Self.sittingDayTimeout)s — "
				+ "treating as a transient backend/network issue (non-gating)."
		)

		// Debate-load latency: XCTClockMetric + an os_signpost interval over navigate→loaded,
		// wrapping the real fetchTranscript triggered by opening the debate. iterationCount = 1
		// because the transcript is one-shot — a second iteration would be an in-memory cache hit.
		let debateContent = app.descendants(matching: .any)
			.matching(identifier: Self.debateContentIdentifier).firstMatch
		let measureOptions = XCTMeasureOptions()
		measureOptions.iterationCount = 1
		var didLoadDebate = false

		measure(metrics: [XCTClockMetric()], options: measureOptions) {
			let interval = signposter.beginInterval(Self.fetchTranscriptSignpostName)
			tapCalendarCell(sittingDayCell)
			didLoadDebate = debateContent.waitForExistence(timeout: Self.debateContentTimeout)
			signposter.endInterval(Self.fetchTranscriptSignpostName, interval)
		}

		try XCTSkipUnless(
			didLoadDebate,
			"Live debate transcript did not load within \(Self.debateContentTimeout)s — "
				+ "treating as a transient backend/network issue (non-gating)."
		)
		XCTAssertGreaterThan(
			debateContent.children(matching: .any).count, 0,
			"Loaded debate content should not be empty"
		)
	}

	// MARK: - Nightly/device gate

	private func skipUnlessNightlyContext() throws {
		let value = ProcessInfo.processInfo.environment[Self.nightlyGateEnvKey]
		try XCTSkipUnless(
			value == Self.nightlyGateEnabledValue,
			"FreshInstallPerfTests runs only in the nightly/device context. "
				+ "Set \(Self.nightlyGateEnvKey)=\(Self.nightlyGateEnabledValue) to run it "
				+ "(the device-nightly schedule wires this). Skipped so it never gates a PR."
		)
	}

	private func attachDuration(_ seconds: TimeInterval, named name: String) {
		let attachment = XCTAttachment(string: "\(name): " + String(format: "%.3f", seconds) + " s")
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
	}

	// MARK: - Onboarding / navigation helpers (mirror OnboardingAndFirstDebateUITests)

	private func dismissAllOnboardingScreens(in app: XCUIApplication) {
		for _ in 0..<Self.maxOnboardingDismissalTaps {
			guard let button = firstHittableButton(in: app, labels: Self.onboardingButtonLabels) else {
				return
			}

			button.tap()
			sleep(Self.onboardingDismissalDelaySeconds)
		}
	}

	private func firstHittableButton(in app: XCUIApplication, labels: [String]) -> XCUIElement? {
		for label in labels {
			let buttons = app.buttons.matching(NSPredicate(format: "label == %@", label))
			for index in 0..<buttons.count {
				let button = buttons.element(boundBy: index)
				if button.exists && button.isHittable {
					return button
				}
			}
		}
		return nil
	}

	private func tapCalendarCell(_ element: XCUIElement) {
		if element.isHittable {
			element.tap()
		} else {
			element.coordinate(
				withNormalizedOffset: CGVector(dx: Self.cellTapOffset, dy: Self.cellTapOffset)
			).tap()
		}
	}
}
