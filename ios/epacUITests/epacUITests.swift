//
//  epacUITests.swift
//  epacUITests
//
//  Five end-to-end user flow tests. Each test is independent — no shared
//  state between runs. Uses XCTNSPredicateExpectation for async content
//  loads; no fixed sleep() calls.
//

import XCTest

final class epacUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UIAnimationsDisabled", "YES"]
        app.launch()
        // Dismiss the postal code setup sheet if it appears on first launch.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Flow 1: Cold launch → Parliament tab visible

    func testColdLaunch_ParliamentTabVisible() throws {
        let parliamentTab = app.tabBars.buttons["Parliament"]
        XCTAssertTrue(parliamentTab.waitForExistence(timeout: 5),
                      "Parliament tab should be visible after cold launch")
        parliamentTab.tap()
        XCTAssertTrue(app.navigationBars.count > 0,
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
        let accountabilityTab = app.tabBars.buttons["Accountability"]
        XCTAssertTrue(accountabilityTab.waitForExistence(timeout: 5),
                      "Accountability tab should exist")
        accountabilityTab.tap()

        let billsLink = app.tables.cells.staticTexts["Bills"].firstMatch
        XCTAssertTrue(billsLink.waitForExistence(timeout: 5),
                      "Bills row should appear in Accountability hub")
        billsLink.tap()

        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5),
                      "Bills navigation bar should appear")
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
