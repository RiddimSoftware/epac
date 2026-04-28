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
        app.launchArguments = [
            "--app-preview-mode",
            "-UIAnimationsDisabled",
            "YES",
            "--app-preview-scene-index",
            "0",
            "--app-preview-test-probes"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppPreviewSequence() throws {
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
    }

    private func waitForScene(headline: String, timeout: TimeInterval) throws {
        let title = app.staticTexts[headline].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Expected scene headline \(headline)")
    }

    private func assertIdentifiersExist(_ identifiers: [String], file: StaticString = #filePath, line: UInt = #line) {
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 0.2), "Expected accessibility identifier \(identifier)", file: file, line: line)
        }
    }

}
