//
//  LaunchPerfTests.swift
//  epacUITests
//

import XCTest

/// Simulator-gated UI perf test for app launch latency and resident memory.
///
/// `XCTApplicationLaunchMetric` measures a warm-ish relaunch: the XCTest runner
/// installs the app once per session and then relaunches it for each iteration,
/// so these numbers are regression signal — not the user-perceived first-tap
/// cold launch on a freshly installed device.
///
/// We intentionally do not pass `-UIAnimationsDisabled`. Launch timing on the
/// simulator should match the path users see, not an animation-suppressed one.
final class LaunchPerfTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndMemoryBaseline() {
        let app = XCUIApplication()
        measure(metrics: [
            XCTApplicationLaunchMetric(),
            XCTMemoryMetric(application: app)
        ]) {
            app.launch()
        }
    }
}
