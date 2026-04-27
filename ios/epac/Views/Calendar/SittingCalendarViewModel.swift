//
//  SittingCalendarViewModel.swift
//  epac
//

import Foundation
import Observation
import SwiftData
import HorizonCalendar
import Sentry

@MainActor
@Observable
class SittingCalendarViewModel {
	var dates = Set<DateComponents>()
	var futureDates = Set<DateComponents>()
	var currentYear: Int = Calendar.current.dateComponents([.year], from: .now).year!
	var loadFailed = false

	var sittingDayCount: Int {
		dates.filter { $0.year == currentYear }.count + futureDates.filter { $0.year == currentYear }.count
	}

	func fetchSittingCalendar(_ year: Int, modelContext: ModelContext, fetch: Fetch) async {
		loadFailed = false
		do {
			var calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			if calendar == nil {
				try await fetch.downloadSittingCalendar(year)
				calendar = try? modelContext.fetch(FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })).first
			}
			let today = Foundation.Calendar.current.startOfDay(for: .now)
			calendar?.sittings.filter { $0 < today }.map {
				Foundation.Calendar.current.dateComponents([.year, .month, .day], from: $0)
			}.forEach { dates.insert($0) }
			calendar?.sittings.filter { $0 >= today }.map {
				Foundation.Calendar.current.dateComponents([.year, .month, .day], from: $0)
			}.forEach { futureDates.insert($0) }
		} catch {
			Log.debug("Failed to fetch SittingCalendar count")
			SentrySDK.capture(error: error)
			loadFailed = true
		}
	}

	func onVisibleDayRangeChanged(_ visibleDayRange: DayComponentsRange, modelContext: ModelContext, fetch: Fetch) {
		if visibleDayRange.lowerBound.components.year! != currentYear {
			currentYear = visibleDayRange.lowerBound.components.year!
			Task {
				await fetchSittingCalendar(visibleDayRange.lowerBound.components.year!, modelContext: modelContext, fetch: fetch)
			}
		} else if visibleDayRange.upperBound.components.year! != currentYear {
			currentYear = visibleDayRange.upperBound.components.year!
			Task {
				await fetchSittingCalendar(visibleDayRange.upperBound.components.year!, modelContext: modelContext, fetch: fetch)
			}
		}
		if visibleDayRange.lowerBound.components.year! != visibleDayRange.upperBound.components.year! {
			let lower = Foundation.Calendar.current.date(from: visibleDayRange.lowerBound.components)!
			let endOfYear = Foundation.Calendar.current.date(from: DateComponents(year: visibleDayRange.lowerBound.components.year!, month: 12, day: 31))!
			let upper = Foundation.Calendar.current.date(from: visibleDayRange.upperBound.components)!
			let startOfYear = Foundation.Calendar.current.date(from: DateComponents(year: visibleDayRange.upperBound.components.year!, month: 1, day: 1))!

			let lowerCount = Foundation.Calendar.current.dateComponents([.day], from: lower, to: endOfYear).day!
			let upperCount = Foundation.Calendar.current.dateComponents([.day], from: startOfYear, to: upper).day!
			if lowerCount > upperCount {
				currentYear = visibleDayRange.lowerBound.components.year!
			} else {
				currentYear = visibleDayRange.upperBound.components.year!
			}
		}
	}
}
