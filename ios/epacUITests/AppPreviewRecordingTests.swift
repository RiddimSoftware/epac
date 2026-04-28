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

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--app-preview-mode", "-UIAnimationsDisabled", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppPreviewSequence() throws {
        try waitForScene(headline: "Your MP. Everything they do.", timeout: 7, hold: 0.5)
        try waitForScene(headline: "Every word. Every vote.", timeout: 8, hold: 0.5)
        try waitForScene(headline: "Hansard. Finally readable.", timeout: 8, hold: 0.5)
        try waitForScene(headline: "Who's influencing them?", timeout: 7, hold: 0.5)
        try waitForScene(headline: "They said it. Then voted against it.", timeout: 7, hold: 0.5)
        try waitForScene(headline: "Democracy. One tap.", timeout: 5, hold: 3)
    }

    private func waitForScene(headline: String, timeout: TimeInterval, hold: TimeInterval) throws {
        let title = app.staticTexts[headline].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Expected scene headline \(headline)")
        Thread.sleep(forTimeInterval: hold)
    }
}
