import XCTest

final class AppStoreScreenshotTests: XCTestCase {

    private let sceneNames = [
        "01-parliament-in-your-pocket",
        "02-see-how-your-mp-votes",
        "03-your-mp-everything-they-do",
        "04-track-a-bill-start-to-finish",
        "05-know-whos-influencing-your-mp",
        "06-contact-them-in-one-tap"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshotSources() throws {
        let app = XCUIApplication()
        for (index, name) in sceneNames.enumerated() {
            app.launchArguments = [
                "-AppStoreScreenshots",
                "-AppStoreScreenshotPage", "\(index)",
                "-UIAnimationsDisabled", "YES"
            ]
            setupSnapshot(app)
            app.launch()

            let headline = app.staticTexts["appStoreScreenshotHeadline"]
            XCTAssertTrue(
                headline.waitForExistence(timeout: 10),
                "Showcase headline should appear for page \(index)"
            )

            snapshot(name, timeWaitingForIdle: 2)
        }
    }
}
