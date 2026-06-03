//
//  SignpostPerfTests.swift
//  epacUITests
//

import XCTest

final class SignpostPerfTests: XCTestCase {
    private enum Constants {
        static let subsystem = "com.riddimsoftware.epac"
        static let category = "performance"
        static let freshStateArgument = "-UI_TEST_FRESH_STATE"
        static let freshStateValue = "1"
        static let uiAnimationsDisabledArgument = "-UIAnimationsDisabled"
        static let uiAnimationsDisabledValue = "YES"
        static let xctestConfigurationEnvironmentKey = "XCTestConfigurationFilePath"
        static let xctestConfigurationEnvironmentValue = "epacUITests"
        static let fetchTranscriptHarnessArgument = "-EPAC_PERF_FETCH_TRANSCRIPT"
        static let performanceHarnessCompletedIdentifier = "performance-harness-completed"
        static let singleIteration = 1
        static let homeTabLabel = "Home"
        static let searchTabLabel = "Search"
        static let homeFeedIdentifier = "home-feed-scroll"
        static let searchQuery = "housing"
        static let onboardingButtonLabels = ["Skip", "Continue", "Next", "Done", "Get Started"]
        static let maxOnboardingDismissalTaps = 10
        static let onboardingDismissalDelaySeconds: UInt32 = 1
        static let launchSettleSeconds: TimeInterval = 1
        static let searchSettleSeconds: TimeInterval = 1
        static let tabTimeout: TimeInterval = 10
        static let homeFeedTimeout: TimeInterval = 10
        static let searchFieldTimeout: TimeInterval = 10
        static let performanceHarnessTimeout: TimeInterval = 10
    }

    private enum SignpostName {
        static let launchModelContainer = "launch.model-container"
        static let launchHomeFeed = "launch.home-feed"
        static let hansardFetchTranscript = "hansard.fetch-transcript"
        static let swiftDataMigrationOpen = "swiftdata.migration-open"
        static let searchHansardRoundTrip = "search.hansard-round-trip"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchModelContainerDuration() {
        measureLaunchSignpost(named: SignpostName.launchModelContainer)
    }

    @MainActor
    func testSwiftDataMigrationOpenDuration() {
        measureLaunchSignpost(named: SignpostName.swiftDataMigrationOpen)
    }

    @MainActor
    func testFirstHomeFeedLoadDuration() {
        measureSignpost(named: SignpostName.launchHomeFeed) {
            let app = self.makeFreshApp()
            app.launch()
            self.dismissAllOnboardingScreens(in: app)
            self.tapTab(Constants.homeTabLabel, in: app)

            let homeFeed = app.descendants(matching: .any).matching(identifier: Constants.homeFeedIdentifier).firstMatch
            XCTAssertTrue(homeFeed.waitForExistence(timeout: Constants.homeFeedTimeout), "Home feed should appear")
            Thread.sleep(forTimeInterval: Constants.launchSettleSeconds)
            app.terminate()
        }
    }

    @MainActor
    func testFetchTranscriptDuration() {
        measureSignpost(named: SignpostName.hansardFetchTranscript) {
            let app = self.makeApp(arguments: [Constants.fetchTranscriptHarnessArgument])
            app.launch()

            let completed = app.descendants(matching: .any)
                .matching(identifier: Constants.performanceHarnessCompletedIdentifier)
                .firstMatch
            XCTAssertTrue(
                completed.waitForExistence(timeout: Constants.performanceHarnessTimeout),
                "Performance harness should finish"
            )
            app.terminate()
        }
    }

    @MainActor
    func testSearchHansardRoundTripDuration() {
        measureSignpost(named: SignpostName.searchHansardRoundTrip) {
            let app = self.makeFreshApp()
            app.launch()
            self.dismissAllOnboardingScreens(in: app)
            self.tapTab(Constants.searchTabLabel, in: app)

            let searchField = app.searchFields.firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: Constants.searchFieldTimeout), "Search field should appear")
            searchField.tap()
            searchField.typeText(Constants.searchQuery)
            Thread.sleep(forTimeInterval: Constants.searchSettleSeconds)
            app.terminate()
        }
    }

    @MainActor
    private func measureLaunchSignpost(named name: String) {
        measureSignpost(named: name) {
            let app = self.makeFreshApp()
            app.launch()
            Thread.sleep(forTimeInterval: Constants.launchSettleSeconds)
            app.terminate()
        }
    }

    @MainActor
    private func measureSignpost(named name: String, block: @escaping () -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = Constants.singleIteration

        measure(
            metrics: [
                XCTOSSignpostMetric(
                    subsystem: Constants.subsystem,
                    category: Constants.category,
                    name: name
                )
            ],
            options: options,
            block: block
        )
    }

    @MainActor
    private func makeFreshApp() -> XCUIApplication {
        makeApp(arguments: [Constants.freshStateArgument, Constants.freshStateValue])
    }

    @MainActor
    private func makeApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            Constants.uiAnimationsDisabledArgument,
            Constants.uiAnimationsDisabledValue
        ] + arguments
        app.launchEnvironment[Constants.xctestConfigurationEnvironmentKey] =
            Constants.xctestConfigurationEnvironmentValue
        return app
    }

    @MainActor
    private func tapTab(_ label: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: Constants.tabTimeout), "\(label) tab should exist")
        tab.tap()
    }

    @MainActor
    private func dismissAllOnboardingScreens(in app: XCUIApplication) {
        for _ in 0..<Constants.maxOnboardingDismissalTaps {
            guard let button = firstHittableButton(in: app, labels: Constants.onboardingButtonLabels) else {
                return
            }

            button.tap()
            sleep(Constants.onboardingDismissalDelaySeconds)
        }
    }

    @MainActor
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
}
