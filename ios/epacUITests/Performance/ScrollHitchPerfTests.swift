//
//  ScrollHitchPerfTests.swift
//  epacUITests
//

import XCTest

@MainActor
final class ScrollHitchPerfTests: XCTestCase {
	private enum Fixture {
		static let name = "45-1-HAN050-E"
		static let speechAdvanceTapCount = 80
		static let elementTimeout: TimeInterval = 15
		static let evidenceNavigationTimeout: TimeInterval = 45
		static let shortSettle: TimeInterval = 0.25
		static let longSettle: TimeInterval = 1.0
	}

	private var app = XCUIApplication()

	override func setUpWithError() throws {
		continueAfterFailure = false
		app = XCUIApplication()
	}

	override func tearDownWithError() throws {
		app.terminate()
	}

	func testLongHansardSpeechScrollHitchMetric_deviceOnly() throws {
		try skipOnUnsupportedRuntime()

		launchEvidenceMode(navigationTarget: "longestSpeech")
		let speechScroll = waitForElement(
			identifier: "speech-view-scroll",
			timeout: Fixture.evidenceNavigationTimeout
		)
		advanceSpeechMessages(in: speechScroll)

		if #available(iOS 26.0, *) {
			measure(metrics: [XCTHitchMetric(application: app)], options: measureOptions) {
				flingScroll(speechScroll)
			}
		}
	}

	func testHomeFeedScrollHitchMetric_deviceOnly() throws {
		try skipOnUnsupportedRuntime()

		launchEvidenceMode()
		let homeFeedScroll = waitForElement(identifier: "home-feed-scroll")

		if #available(iOS 26.0, *) {
			measure(metrics: [XCTHitchMetric(application: app)], options: measureOptions) {
				flingScroll(homeFeedScroll)
			}
		}
	}

	func testHansardNavigationTransitionMetric_deviceOnly() throws {
		try skipOnUnsupportedRuntime()

		launchEvidenceMode(navigationTarget: "sitting")
		let debateContent = waitForElement(
			identifier: "debate-content",
			timeout: Fixture.evidenceNavigationTimeout
		)
		XCTAssertTrue(debateContent.exists, "Seeded sitting overview should be visible before measuring navigation.")

		measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric], options: measureOptions) {
			let longestSubject = waitForElement(identifier: "debate-longest-subject-row")
			longestSubject.tap()
			_ = waitForElement(identifier: "speech-view-scroll")
			app.navigationBars.buttons.firstMatch.tap()
			_ = waitForElement(identifier: "debate-content")
		}
	}

	private var measureOptions: XCTMeasureOptions {
		let options = XCTMeasureOptions()
		options.iterationCount = 3
		return options
	}

	private func skipOnUnsupportedRuntime() throws {
		#if targetEnvironment(simulator)
		throw XCTSkip("XCTHitchMetric and frame-rate signpost measurements are unsupported on Simulator; run make perf-device on a connected iOS 26 device.")
		#else
		if #unavailable(iOS 26.0) {
			throw XCTSkip("XCTHitchMetric requires iOS 26.0 or newer.")
		}
		#endif
	}

	private func launchEvidenceMode(navigationTarget: String? = nil) {
		app.launchEnvironment["EPAC_EVIDENCE_MODE"] = "1"
		app.launchEnvironment["EPAC_EVIDENCE_FIXTURE"] = Fixture.name
		if let navigationTarget {
			app.launchEnvironment["EPAC_PERF_NAVIGATION_TARGET"] = navigationTarget
		}
		app.launch()
	}

	private func waitForElement(
		identifier: String,
		timeout: TimeInterval = Fixture.elementTimeout
	) -> XCUIElement {
		let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
		XCTAssertTrue(
			element.waitForExistence(timeout: timeout),
			"Expected \(identifier) within \(timeout)s. Current UI hierarchy:\n\(app.debugDescription)"
		)
		return element
	}

	private func advanceSpeechMessages(in speechScroll: XCUIElement) {
		Thread.sleep(forTimeInterval: Fixture.longSettle)
		let tapPoint = speechScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
		for _ in 0..<Fixture.speechAdvanceTapCount {
			tapPoint.tap()
		}
		Thread.sleep(forTimeInterval: Fixture.longSettle)
	}

	private func flingScroll(_ element: XCUIElement) {
		let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
		let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
		start.press(forDuration: 0.01, thenDragTo: end)
		Thread.sleep(forTimeInterval: Fixture.shortSettle)
	}
}
