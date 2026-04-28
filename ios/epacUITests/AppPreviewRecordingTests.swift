//
//  AppPreviewRecordingTests.swift
//  epacUITests
//
//  Drives the hidden App Store preview route used by
//  scripts/marketing/record-app-preview.sh.
//

import XCTest

final class AppPreviewRecordingTests: XCTestCase {
    private var app: XCUIApplication!
    private let recordingSceneHold: TimeInterval = 2.75
    private var isRecordingRun: Bool {
        name.contains("testAppPreviewRecordingSequence") ||
        ProcessInfo.processInfo.environment["APP_PREVIEW_RECORDING"] == "1"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 60
        app = XCUIApplication()
        if isRecordingRun {
            app.launchArguments = ["--app-preview-mode", "-UIAnimationsDisabled", "YES"]
            app.launchEnvironment["EPAC_APP_PREVIEW_MODE"] = "1"
            app.launchEnvironment["EPAC_APP_PREVIEW_MANUAL_SEQUENCE"] = "1"
        } else {
            app.launchArguments = [
                "--app-preview-mode",
                "-UIAnimationsDisabled",
                "YES",
                "--app-preview-scene-index",
                "0",
                "--app-preview-test-probes"
            ]
            app.launchEnvironment["EPAC_APP_PREVIEW_MODE"] = "1"
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppPreviewSequence() throws {
        try runAppPreviewSequence()
    }

    func testAppPreviewRecordingSequence() throws {
        try runAppPreviewSequence()
    }

    private func runAppPreviewSequence() throws {
        if !isRecordingRun {
            try waitForScene(headline: "Your MP. Everything they do.", timeout: 7)
            assertIdentifiersExist([
                "home-feed-scroll",
                "home-feed-today-card",
                "home-feed-my-mp-link",
                "mp-profile-scroll",
                "mp-profile-speech-list",
                "mp-profile-speech-row-0",
                "speech-view-scroll",
                "parliament-sitting-row-0",
                "lobbying-list-scroll",
                "accountability-lobbying-link",
                "vote-detail-scroll",
                "vote-list-row-0",
                "vote-detail-mp-list",
                "mp-profile-contact-button",
                "contact-sheet-scroll",
                "contact-message-field"
            ])
            return
        }

        // Recording path: deterministic tap-to-advance with short sleep chunks.
        // Manual sequencing avoids the flaky XCTest runner timing in EPAC-537.
        try waitForScene(headline: "Your MP. Everything they do.", timeout: 10, hold: recordingSceneHold)
        advanceToNextScene()
        try waitForScene(headline: "Every word. Every vote.", timeout: 5, hold: recordingSceneHold)
        advanceToNextScene()
        try waitForScene(headline: "Hansard. Finally readable.", timeout: 5, hold: recordingSceneHold)
        advanceToNextScene()
        try waitForScene(headline: "Who's influencing them?", timeout: 5, hold: recordingSceneHold)
        advanceToNextScene()
        try waitForScene(headline: "They said it. Then voted against it.", timeout: 5, hold: recordingSceneHold)
        advanceToNextScene()
        try waitForScene(headline: "Democracy. One tap.", timeout: 5, hold: recordingSceneHold)
    }

    private func advanceToNextScene() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForScene(
        headline: String,
        timeout: TimeInterval,
        hold: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let title = app.staticTexts[headline].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Expected scene headline \(headline)", file: file, line: line)
        if let hold {
            holdScene(for: hold)
        }
    }

    private func holdScene(for duration: TimeInterval) {
        var remaining = duration
        while remaining > 0 {
            let interval = min(remaining, 1.0)
            Thread.sleep(forTimeInterval: interval)
            remaining -= interval
        }
    }

    private func assertIdentifiersExist(_ identifiers: [String], file: StaticString = #filePath, line: UInt = #line) {
        guard let firstIdentifier = identifiers.first else { return }
        let firstProbe = app.staticTexts[firstIdentifier].firstMatch
        XCTAssertTrue(firstProbe.waitForExistence(timeout: 2), "Expected accessibility identifier \(firstIdentifier)", file: file, line: line)

        let labels = Set(app.staticTexts.allElementsBoundByIndex.map(\.label))
        for identifier in identifiers {
            XCTAssertTrue(labels.contains(identifier), "Expected accessibility identifier \(identifier)", file: file, line: line)
        }
    }

}
