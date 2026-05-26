//
//  epacUITestsLaunchTests.swift
//  epacUITests
//
//  Created by Sunny on 2024-12-08.
//

import XCTest

final class epacUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            let metrics: [XCTMetric] = [XCTApplicationLaunchMetric()]
            measure(metrics: metrics) {
                XCUIApplication().launch()
            }
        }
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
