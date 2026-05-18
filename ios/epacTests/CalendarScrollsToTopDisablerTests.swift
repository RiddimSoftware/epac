@testable import epac
import Testing
import UIKit

@MainActor
struct CalendarScrollsToTopDisablerTests {
	@Test func disablesOnlyCalendarScrollViewScrollsToTop() {
		let root = UIView()
		let regularScrollView = UIScrollView()
		let calendarScrollView = CalendarScrollView()
		root.addSubview(regularScrollView)
		root.addSubview(calendarScrollView)

		let didDisableCalendarScrollView = CalendarScrollsToTopDisabler.disable(in: root)

		#expect(didDisableCalendarScrollView)
		#expect(regularScrollView.scrollsToTop)
		#expect(!calendarScrollView.scrollsToTop)
	}

	@Test func reportsNoCalendarScrollViewWhenHierarchyDoesNotContainOne() {
		let root = UIView()
		root.addSubview(UIScrollView())

		let didDisableCalendarScrollView = CalendarScrollsToTopDisabler.disable(in: root)

		#expect(!didDisableCalendarScrollView)
	}
}

private final class CalendarScrollView: UIScrollView {}
