//
//  SittingCalendarScrollCoordinator.swift
//  epac
//
//  Created on 2026-05-26.
//

@MainActor
struct SittingCalendarScrollCoordinator {
	enum Decision: Equatable {
		case scrollNow
		case deferredUntilMounted
		case skippedUnmounted
	}

	private(set) var isMounted = false
	private(set) var hasPendingScrollToToday = false

	mutating func calendarDidMount() -> Bool {
		isMounted = true
		guard hasPendingScrollToToday else { return false }
		hasPendingScrollToToday = false
		return true
	}

	mutating func calendarDidUnmount() {
		isMounted = false
	}

	mutating func requestScrollToToday(deferIfUnmounted: Bool) -> Decision {
		guard isMounted else {
			if deferIfUnmounted {
				hasPendingScrollToToday = true
				return .deferredUntilMounted
			}
			return .skippedUnmounted
		}

		hasPendingScrollToToday = false
		return .scrollNow
	}
}
