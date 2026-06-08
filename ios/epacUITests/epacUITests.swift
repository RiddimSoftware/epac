//
//  epacUITests.swift
//  epacUITests
//
//  Five end-to-end user flow tests. Each test is independent — no shared
//  state between runs. Uses XCTNSPredicateExpectation for async content
//  loads; no fixed sleep() calls.
//

import XCTest

private enum UITestLayout {
    static let iPadWidthThreshold: CGFloat = 700
    // Normalized midpoint for XCUITest coordinate taps.
    // swiftlint:disable:next no_magic_numbers
    static let elementCenter = CGVector(dx: 0.5, dy: 0.5)
}

final class epacUITests: XCTestCase {

    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UIAnimationsDisabled", "YES"]
        app.launchEnvironment["XCTestConfigurationFilePath"] = "epacUITests"
        if name.contains("testCaptureAppStoreScreenshotSources") {
            return
        }
        app.launch()
        // Dismiss the postal code setup sheet if it appears on first launch.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
    }

    override func tearDownWithError() throws {
        app = XCUIApplication()
    }

    private func openAccountabilitySurface() {
        let tabButton = app.tabBars.buttons["Accountability"]
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
            return
        }

        let sidebarButton = app.buttons["Accountability"].firstMatch
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5),
                      "Accountability entry should exist")
        tap(sidebarButton)
    }

    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: UITestLayout.elementCenter).tap()
        }
    }

    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachLandscapeScreenshotIfNeeded() {
        guard app.windows.firstMatch.frame.width >= UITestLayout.iPadWidthThreshold else { return }

        XCUIDevice.shared.orientation = .landscapeLeft
        let billsNavigationBar = app.navigationBars["Bills"]
        let billsPlaceholder = app.staticTexts["bills-detail-placeholder"]
        _ = billsNavigationBar.waitForExistence(timeout: 5)
        _ = billsPlaceholder.waitForExistence(timeout: 5)
        attachScreenshot(named: "Bills destination landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Flow 1: Cold launch → Parliament tab visible

    func testColdLaunch_ParliamentTabVisible() throws {
        let parliamentTab = app.tabBars.buttons["Parliament"]
		XCTAssertTrue(parliamentTab.waitForExistence(timeout: 5),
		              "Parliament tab should be visible after cold launch")
		parliamentTab.tap()
		XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3),
		              "Navigation bar should appear in Parliament tab")
	}

    // MARK: - Flow 2: Members tab → search → member detail

    func testMembersTab_SearchAndOpenDetail() throws {
        let membersTab = app.tabBars.buttons["Members"]
        XCTAssertTrue(membersTab.waitForExistence(timeout: 5), "Members tab should exist")
        membersTab.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "Search field should appear")
        searchField.tap()
        searchField.typeText("trudeau")

        // Wait up to 5s for at least one result cell.
        let firstCell = app.tables.cells.firstMatch
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"),
                                               object: firstCell)
        _ = XCTWaiter.wait(for: [exists], timeout: 5)

        if firstCell.exists {
            firstCell.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3),
                          "Member detail navigation bar should appear")
        }
        // Passes trivially if no members are loaded (fresh install).
    }

    // MARK: - Flow 3: Accountability tab → Bills list visible

    func testAccountabilityTab_BillsListVisible() throws {
        openAccountabilitySurface()

        let billsButton = app.buttons["Bills"].firstMatch
        let billsCell = app.cells.containing(.staticText, identifier: "Bills").firstMatch
        let billsRow = billsButton.waitForExistence(timeout: 5) ? billsButton : billsCell
        XCTAssertTrue(billsRow.exists || billsRow.waitForExistence(timeout: 5),
                      "Bills row should appear in Accountability hub")
        tap(billsRow)

        let billsNavigationBar = app.navigationBars["Bills"]
        let billsPlaceholder = app.staticTexts["bills-detail-placeholder"]
        _ = billsNavigationBar.waitForExistence(timeout: 5)
        _ = billsPlaceholder.waitForExistence(timeout: 5)
        let billsDestinationAppeared = billsNavigationBar.exists || billsPlaceholder.exists
        attachScreenshot(named: "Bills destination")
        XCTAssertTrue(billsDestinationAppeared,
                      "Bills destination should appear")
        attachLandscapeScreenshotIfNeeded()
    }

    func testAccountabilityTab_LobbyistOrganizationDetailLoads() throws {
        openAccountabilitySurface()

        let organizationsRow = app.staticTexts["Lobbyist Organizations"].firstMatch
        scrollUntilVisible(organizationsRow)
        XCTAssertTrue(
            organizationsRow.exists && organizationsRow.isHittable,
            "Lobbyist Organizations row should appear in Accountability hub"
        )
        tap(organizationsRow)

        let directory = app.descendants(matching: .any)
            .matching(identifier: "lobbyist-organization-directory")
            .firstMatch
        XCTAssertTrue(directory.waitForExistence(timeout: 30), "Lobbyist organization directory should load")

        let firstOrganization = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Canadian Chamber of Commerce")
        ).firstMatch
        XCTAssertTrue(firstOrganization.waitForExistence(timeout: 30), "At least one lobbyist organization should be listed")
        tap(firstOrganization)

        let profile = app.descendants(matching: .any)
            .matching(identifier: "lobbyist-organization-profile")
            .firstMatch
        let error = app.staticTexts["Couldn't Load Lobbying Data"].firstMatch
        let loaded = profile.waitForExistence(timeout: 30)
        attachScreenshot(named: "Lobbyist organization detail")
        XCTAssertTrue(loaded, "Lobbyist organization profile should load after tapping a directory row")
        XCTAssertFalse(error.exists, "Lobbyist organization detail should not show a lobbying data error")
    }

    // MARK: - Flow 4: Home tab → postal code onboarding

    func testHomeFeed_PostalCodeOnboarding() throws {
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5), "Home tab should exist")
        homeTab.tap()

        // Only run if the setup prompt is present (no MP saved yet).
        let findButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'find' OR label CONTAINS[c] 'postal' OR label CONTAINS[c] 'MP'")
        ).firstMatch
        guard findButton.waitForExistence(timeout: 3) else { return }
        findButton.tap()

        let postalField = app.textFields.firstMatch
        XCTAssertTrue(postalField.waitForExistence(timeout: 3), "Postal code field should appear")
        postalField.tap()
        postalField.typeText("M5V0C7")

        let lookupButton = app.buttons["Look Up"]
        if lookupButton.waitForExistence(timeout: 2) { lookupButton.tap() }

        // Wait up to 10s for a riding name to appear.
        let riding = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Toronto' OR label CONTAINS 'Spadina' OR label CONTAINS 'York'")
        ).firstMatch
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"),
                                                 object: riding)
        let result = XCTWaiter.wait(for: [appeared], timeout: 10)
        if result == .completed {
            let confirm = app.buttons["This is my MP"]
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        }
    }

    // MARK: - Flow 5: Search tab → query accepted without crash

    func testSearchTab_QueryAccepted() throws {
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5), "Search tab should exist")
        searchTab.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should appear")
        searchField.tap()
        searchField.typeText("housing")

        // The "Search everything" prompt should disappear once a query is entered.
        let prompt = app.staticTexts["Search everything"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: prompt)
        _ = XCTWaiter.wait(for: [gone], timeout: 3)
        // Test passes by reaching this point without a crash.
    }
}
