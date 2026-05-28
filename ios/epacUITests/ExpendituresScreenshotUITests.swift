//
//  ExpendituresScreenshotUITests.swift
//  epacUITests
//

import XCTest

private struct ExpendituresCaptureConfiguration: Decodable {
	let directory: String
	let name: String
	let orientation: String

	private enum CodingKeys: String, CodingKey {
		case directory
		case name
		case orientation
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		directory = try container.decode(String.self, forKey: .directory)
		name = try container.decode(String.self, forKey: .name)
		orientation = try container.decode(String.self, forKey: .orientation)
	}
}

private enum ExpendituresCaptureDefaults {
	static let configurationPath = "/tmp/epac-expenditures-screenshot.json"
	static let portraitOrientation = "portrait"
	static let landscapeOrientation = "landscape"
}

final class ExpendituresScreenshotUITests: XCTestCase {
	private var captureConfiguration: ExpendituresCaptureConfiguration?
	private var outputDirectory: URL?

	override func setUpWithError() throws {
		continueAfterFailure = false
		let configurationURL = URL(fileURLWithPath: ExpendituresCaptureDefaults.configurationPath)
		guard FileManager.default.fileExists(atPath: configurationURL.path) else {
			throw XCTSkip("Screenshot capture is opt-in.")
		}
		let data = try Data(contentsOf: configurationURL)
		let configuration = try JSONDecoder().decode(ExpendituresCaptureConfiguration.self, from: data)
		captureConfiguration = configuration
		outputDirectory = URL(fileURLWithPath: configuration.directory, isDirectory: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(atPath: ExpendituresCaptureDefaults.configurationPath)
	}

	func testCaptureExpendituresScreen() throws {
		let app = XCUIApplication()
		app.launchArguments = ["-UIAnimationsDisabled", "YES"]
		app.launchEnvironment["EPAC_EVIDENCE_MODE"] = "1"

		applyRequestedOrientation()
		app.launch()
		navigateToExpenditures(in: app)

		let title = app.navigationBars["Expenditures"].firstMatch
		let placeholder = app.staticTexts["Select an Expenditure"].firstMatch
		XCTAssertTrue(
			title.waitForExistence(timeout: 8) || placeholder.waitForExistence(timeout: 8),
			"Expenditures screen should be visible before capture"
		)

		try writeScreenshot()
	}

	private func navigateToExpenditures(in app: XCUIApplication) {
		if app.tabBars.buttons["Accountability"].waitForExistence(timeout: 4) {
			app.tabBars.buttons["Accountability"].tap()
		} else {
			let accountabilityButton = app.buttons["Accountability"].firstMatch
			XCTAssertTrue(accountabilityButton.waitForExistence(timeout: 4), "Accountability navigation should be visible")
			accountabilityButton.tap()
		}

		let expendituresRow = app.staticTexts["Expenditures"].firstMatch
		XCTAssertTrue(expendituresRow.waitForExistence(timeout: 6), "Expenditures row should be visible")
		expendituresRow.tap()
	}

	private func applyRequestedOrientation() {
		switch captureConfiguration?.orientation {
		case ExpendituresCaptureDefaults.landscapeOrientation:
			XCUIDevice.shared.orientation = .landscapeLeft
		default:
			XCUIDevice.shared.orientation = .portrait
		}
	}

	private func writeScreenshot() throws {
		let directory = try XCTUnwrap(outputDirectory)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let name = try XCTUnwrap(captureConfiguration?.name)
		let url = directory.appendingPathComponent(name)
		try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
	}
}
