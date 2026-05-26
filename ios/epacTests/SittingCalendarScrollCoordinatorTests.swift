@testable import epac
import Testing

@MainActor
struct SittingCalendarScrollCoordinatorTests {
	@Test func scrollRequestBeforeMountDefersUntilCalendarAppears() {
		var coordinator = SittingCalendarScrollCoordinator()

		let firstDecision = coordinator.requestScrollToToday(deferIfUnmounted: true)
		#expect(firstDecision == .deferredUntilMounted)
		#expect(coordinator.hasPendingScrollToToday)

		let shouldReplayPendingScroll = coordinator.calendarDidMount()
		#expect(shouldReplayPendingScroll)
		#expect(!coordinator.hasPendingScrollToToday)

		let mountedDecision = coordinator.requestScrollToToday(deferIfUnmounted: true)
		#expect(mountedDecision == .scrollNow)
	}

	@Test func manualScrollCanSkipInsteadOfQueueingWhenUnmounted() {
		var coordinator = SittingCalendarScrollCoordinator()

		let decision = coordinator.requestScrollToToday(deferIfUnmounted: false)

		#expect(decision == .skippedUnmounted)
		#expect(!coordinator.hasPendingScrollToToday)
	}
}
