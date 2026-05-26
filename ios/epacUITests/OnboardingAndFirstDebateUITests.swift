//
//  OnboardingAndFirstDebateUITests.swift
//  epacUITests
//

import XCTest

final class OnboardingAndFirstDebateUITests: XCTestCase {
	private static let freshStateArgument = "-UI_TEST_FRESH_STATE"
	private static let enabledLaunchValue = "1"
	private static let parliamentTabLabel = "Parliament"
	private static let sittingDayIdentifier = "sitting-day-cell"
	private static let debateContentIdentifier = "debate-content"
	private static let maxOnboardingDismissalTaps = 10
	private static let onboardingDismissalDelaySeconds: UInt32 = 1
	private static let parliamentTabTimeout: TimeInterval = 10
	private static let sittingDayTimeout: TimeInterval = 15
	private static let debateContentTimeout: TimeInterval = 15
	private static let cellTapOffset = 0.5
	private static let onboardingButtonLabels = ["Skip", "Continue", "Next", "Done", "Get Started"]

	private var app = XCUIApplication()

	override func setUpWithError() throws {
		continueAfterFailure = false
		app = XCUIApplication()
	}

	override func tearDownWithError() throws {
		app.terminate()
	}

	func test_freshInstall_dismissesOnboarding_opensFirstDebate() throws {
		app.launchArguments += [Self.freshStateArgument, Self.enabledLaunchValue]
		app.launch()

		dismissAllOnboardingScreens(in: app)

		let parliamentTab = app.tabBars.buttons[Self.parliamentTabLabel]
		XCTAssertTrue(parliamentTab.waitForExistence(timeout: Self.parliamentTabTimeout), "Parliament tab should exist")
		parliamentTab.tap()

		let sittingDayCell = app.descendants(matching: .any).matching(identifier: Self.sittingDayIdentifier).firstMatch
		XCTAssertTrue(sittingDayCell.waitForExistence(timeout: Self.sittingDayTimeout), "Expected a sitting day cell")
		tapCalendarCell(sittingDayCell)

		let debateContent = app.descendants(matching: .any).matching(identifier: Self.debateContentIdentifier).firstMatch
		guard debateContent.waitForExistence(timeout: Self.debateContentTimeout) else {
			XCTFail("Expected debate content. Current UI hierarchy:\n\(app.debugDescription)")
			return
		}
		XCTAssertGreaterThan(debateContent.children(matching: .any).count, 0, "Debate content should not be empty")
	}

	private func dismissAllOnboardingScreens(in app: XCUIApplication) {
		for _ in 0..<Self.maxOnboardingDismissalTaps {
			guard let button = firstHittableButton(in: app, labels: Self.onboardingButtonLabels) else {
				return
			}

			button.tap()
			sleep(Self.onboardingDismissalDelaySeconds)
		}
	}

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

	private func tapCalendarCell(_ element: XCUIElement) {
		if element.isHittable {
			element.tap()
		} else {
			element.coordinate(
				withNormalizedOffset: CGVector(dx: Self.cellTapOffset, dy: Self.cellTapOffset)
			).tap()
		}
	}
}
