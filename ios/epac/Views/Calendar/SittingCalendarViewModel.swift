//
//  SittingCalendarViewModel.swift
//  epac

import Foundation
import HorizonCalendar
import Observation
import Sentry
import SwiftData

// Protocol describing the calendar-download capability SittingCalendarViewModel
// needs. Fetch conforms in production; tests supply a mock without network I/O.
protocol SittingCalendarFetching: Sendable {
	func downloadSittingCalendar(_ year: Int) async throws
}

// Fetch already implements downloadSittingCalendar — conformance is additive.
extension Fetch: SittingCalendarFetching {}

@MainActor
@Observable
class SittingCalendarViewModel {
	var dates = Set<DateComponents>()
	var futureDates = Set<DateComponents>()
	var currentYear: Int = Calendar.current.dateComponents([.year], from: .now).year!
	var loadFailed = false
	private var loadGeneration = 0

	var sittingDayCount: Int {
		dates.filter { $0.year == currentYear }.count + futureDates.filter { $0.year == currentYear }.count
	}

	func upcomingSittingDates(
		from startDate: Date = .now,
		throughDays dayCount: Int = 30,
		calendar: Foundation.Calendar = .current
	) -> [Date] {
		let start = calendar.startOfDay(for: startDate)
		guard let end = calendar.date(byAdding: .day, value: dayCount, to: start) else {
			return []
		}
		return dates.union(futureDates)
			.compactMap { calendar.date(from: $0) }
			.map { calendar.startOfDay(for: $0) }
			.filter { $0 >= start && $0 <= end }
			.sorted()
	}

	// fetch param typed as the protocol so tests can inject a mock without
	// a real ModelContainer-backed Fetch actor.
	func fetchSittingCalendar(_ year: Int, modelContext: ModelContext, fetch: any SittingCalendarFetching) async {
		let generation = nextLoadGeneration()
		loadFailed = false
		do {
			var calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			if calendar == nil {
				try await fetch.downloadSittingCalendar(year)
				calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			}
			guard isCurrentLoad(generation) else { return }
			let splitDates = makeDateComponentSets(from: calendar?.sittings ?? [])
			dates.formUnion(splitDates.past)
			futureDates.formUnion(splitDates.future)
		} catch {
			guard isCurrentLoad(generation) else { return }
			Log.debug("Failed to fetch SittingCalendar count")
			SentrySDK.capture(error: error)
			loadFailed = true
		}
	}

	/// Force-reloads the current year from the network, bypassing the SwiftData cache.
	func refresh(modelContext: ModelContext, fetch: any SittingCalendarFetching) async {
		let year = currentYear
		let generation = nextLoadGeneration()
		loadFailed = false
		do {
			try await fetch.downloadSittingCalendar(year)
			let calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			guard isCurrentLoad(generation), currentYear == year else { return }
			let splitDates = makeDateComponentSets(from: calendar?.sittings ?? [])
			dates = dates.filter { $0.year != year }
			futureDates = futureDates.filter { $0.year != year }
			dates.formUnion(splitDates.past)
			futureDates.formUnion(splitDates.future)
		} catch {
			guard isCurrentLoad(generation) else { return }
			Log.debug("SittingCalendarViewModel.refresh failed: \(error.localizedDescription)")
			SentrySDK.capture(error: error)
			loadFailed = true
		}
	}

	func onVisibleDayRangeChanged(_ visibleDayRange: DayComponentsRange, modelContext: ModelContext, fetch: any SittingCalendarFetching) {
		guard let lowerYear = visibleDayRange.lowerBound.components.year,
					let upperYear = visibleDayRange.upperBound.components.year else {
			return
		}

		if lowerYear != currentYear {
			currentYear = lowerYear
			Task {
				await fetchSittingCalendar(lowerYear, modelContext: modelContext, fetch: fetch)
			}
		} else if upperYear != currentYear {
			currentYear = upperYear
			Task {
				await fetchSittingCalendar(upperYear, modelContext: modelContext, fetch: fetch)
			}
		}
		if lowerYear != upperYear,
			 let lower = Foundation.Calendar.current.date(from: visibleDayRange.lowerBound.components),
			 let endOfYear = Foundation.Calendar.current.date(from: DateComponents(year: lowerYear, month: 12, day: 31)),
			 let upper = Foundation.Calendar.current.date(from: visibleDayRange.upperBound.components),
			 let startOfYear = Foundation.Calendar.current.date(from: DateComponents(year: upperYear, month: 1, day: 1)),
			 let lowerCount = Foundation.Calendar.current.dateComponents([.day], from: lower, to: endOfYear).day,
			 let upperCount = Foundation.Calendar.current.dateComponents([.day], from: startOfYear, to: upper).day {

			if lowerCount > upperCount {
				currentYear = lowerYear
			} else {
				currentYear = upperYear
			}
		}
	}

	private func nextLoadGeneration() -> Int {
		loadGeneration += 1
		return loadGeneration
	}

	private func isCurrentLoad(_ generation: Int) -> Bool {
		generation == loadGeneration
	}

	private func makeDateComponentSets(from sittings: [Date]) -> (past: Set<DateComponents>, future: Set<DateComponents>) {
		let calendar = Foundation.Calendar.current
		let today = calendar.startOfDay(for: .now)
		var past = Set<DateComponents>()
		var future = Set<DateComponents>()
		for sitting in sittings {
			let components = calendar.dateComponents([.year, .month, .day], from: sitting)
			if sitting < today {
				past.insert(components)
			} else {
				future.insert(components)
			}
		}
		return (past, future)
	}
}
