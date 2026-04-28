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
        try waitForScene(
            headline: "Your MP. Everything they do.",
            timeout: 10,
            identifiers: ["home-feed-scroll", "home-feed-today-card", "home-feed-my-mp-link"],
            hold: 0.5
        )
        try waitForScene(
            headline: "Every word. Every vote.",
            timeout: 12,
            identifiers: ["mp-profile-scroll", "mp-profile-speech-list", "mp-profile-speech-row-0"],
            hold: 0.5
        )
        try waitForScene(
            headline: "Hansard. Finally readable.",
            timeout: 12,
            identifiers: ["speech-view-scroll", "parliament-sitting-row-0"],
            hold: 0.5
        )
        try waitForScene(
            headline: "Who's influencing them?",
            timeout: 12,
            identifiers: ["lobbying-list-scroll", "accountability-lobbying-link"],
            hold: 0.5
        )
        try waitForScene(
            headline: "They said it. Then voted against it.",
            timeout: 12,
            identifiers: ["vote-detail-scroll", "vote-list-row-0", "vote-detail-mp-list"],
            hold: 0.5
        )
        try waitForScene(
            headline: "Democracy. One tap.",
            timeout: 10,
            identifiers: ["mp-profile-contact-button", "contact-sheet-scroll", "contact-message-field"],
            hold: 3
        )
    }

    private func waitForScene(
        headline: String,
        timeout: TimeInterval,
        identifiers: [String],
        hold: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let title = app.staticTexts[headline].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Expected scene headline \(headline)", file: file, line: line)
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 1), "Expected accessibility identifier \(identifier)", file: file, line: line)
        }
        Thread.sleep(forTimeInterval: hold)
    }

}
