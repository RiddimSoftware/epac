//
//  SittingCalendarViewModel.swift
//  epac

import Foundation
import HorizonCalendar
import Observation
import SwiftData

@MainActor
@Observable
class SittingCalendarViewModel {
	var dates = Set<DateComponents>()
	var futureDates = Set<DateComponents>()
	var currentYear: Int = Calendar.current.dateComponents([.year], from: .now).year!
	var loadFailed = false
	var sittingDateComponents: Set<DateComponents> {
		dates.union(futureDates)
	}
	private var loadGeneration = 0
	private var browseHansardSitting: (any BrowseHansardSittingUseCase)?
	@ObservationIgnored private var deferredFetchTask: Task<Void, Never>?

	private enum CalendarBoundary {
		static let january = 1
		static let firstDayOfMonth = 1
		static let december = 12
		static let lastDayOfDecember = 31
	}

	init(browseHansardSitting: (any BrowseHansardSittingUseCase)? = nil) {
		self.browseHansardSitting = browseHansardSitting
	}

	deinit {
		deferredFetchTask?.cancel()
	}

	func configure(browseHansardSitting: any BrowseHansardSittingUseCase) {
		self.browseHansardSitting = browseHansardSitting
	}

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

	func loadSittingCalendarCacheFirst(
		_ year: Int,
		modelContext: ModelContext,
		fetch: Fetch,
		forceRemoteRefresh: Bool = false
	) {
		let generation = nextLoadGeneration()
		loadFailed = false
		loadCachedSittingCalendar(year, modelContext: modelContext)
		startDeferredFetch(
			year,
			modelContext: modelContext,
			fetch: fetch,
			generation: generation,
			forceRemoteRefresh: forceRemoteRefresh
		)
	}

	func fetchSittingCalendar(_ year: Int, modelContext: ModelContext, fetch: Fetch) async {
		let generation = nextLoadGeneration()
		deferredFetchTask?.cancel()
		deferredFetchTask = nil
		loadFailed = false
		await fetchSittingCalendar(
			year,
			modelContext: modelContext,
			fetch: fetch,
			generation: generation,
			forceRemoteRefresh: false
		)
	}

	private func fetchSittingCalendar(
		_ year: Int,
		modelContext: ModelContext,
		fetch: Fetch,
		generation: Int,
		forceRemoteRefresh: Bool
	) async {
		do {
			if forceRemoteRefresh {
				try await fetch.downloadSittingCalendar(year)
			}
			let result = try await loadSittingWindow(year: year, modelContext: modelContext, fetch: fetch)
			guard !Task.isCancelled, isCurrentLoad(generation) else { return }
			replaceSittingDates(for: year, with: result.sittingDates)
			loadFailed = false
		} catch {
			guard !Task.isCancelled, isCurrentLoad(generation) else { return }
			Log.debug("Failed to fetch SittingCalendar count")
			Telemetry.recordError(error)
			loadFailed = true
		}
	}

	/// Force-reloads the current year from the network, bypassing the SwiftData cache.
	func refresh(modelContext: ModelContext, fetch: Fetch) async {
		let year = currentYear
		let generation = nextLoadGeneration()
		deferredFetchTask?.cancel()
		deferredFetchTask = nil
		loadFailed = false
		do {
			if browseHansardSitting == nil {
				try await fetch.downloadSittingCalendar(year)
			}
			let result = try await loadSittingWindow(year: year, modelContext: modelContext, fetch: fetch)
			guard isCurrentLoad(generation), currentYear == year else { return }
			replaceSittingDates(for: year, with: result.sittingDates)
		} catch {
			guard isCurrentLoad(generation) else { return }
			Log.debug("SittingCalendarViewModel.refresh failed: \(error.localizedDescription)")
			Telemetry.recordError(error)
			loadFailed = true
		}
	}

	func onVisibleDayRangeChanged(_ visibleDayRange: DayComponentsRange, modelContext: ModelContext, fetch: Fetch) {
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
			 let endOfYear = Foundation.Calendar.current.date(
				from: DateComponents(
					year: lowerYear,
					month: CalendarBoundary.december,
					day: CalendarBoundary.lastDayOfDecember
				)
			 ),
			 let upper = Foundation.Calendar.current.date(from: visibleDayRange.upperBound.components),
			 let startOfYear = Foundation.Calendar.current.date(
				from: DateComponents(
					year: upperYear,
					month: CalendarBoundary.january,
					day: CalendarBoundary.firstDayOfMonth
				)
			 ),
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

	private func startDeferredFetch(
		_ year: Int,
		modelContext: ModelContext,
		fetch: Fetch,
		generation: Int,
		forceRemoteRefresh: Bool
	) {
		deferredFetchTask?.cancel()
		deferredFetchTask = Task {
			await fetchSittingCalendar(
				year,
				modelContext: modelContext,
				fetch: fetch,
				generation: generation,
				forceRemoteRefresh: forceRemoteRefresh
			)
			if isCurrentLoad(generation) {
				deferredFetchTask = nil
			}
		}
	}

	private func loadCachedSittingCalendar(_ year: Int, modelContext: ModelContext) {
		do {
			let descriptor = FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })
			let cachedDates = try modelContext.fetch(descriptor).first?.sittings ?? []
			replaceSittingDates(for: year, with: cachedDates)
		} catch {
			Log.debug("Failed to load cached SittingCalendar count")
			Telemetry.recordError(error)
			loadFailed = true
		}
	}

	private func loadSittingWindow(
		year: Int,
		modelContext: ModelContext,
		fetch: Fetch
	) async throws -> BrowseHansardSitting.Result {
		guard let startDate = Foundation.Calendar.current.date(
			from: DateComponents(year: year, month: CalendarBoundary.january, day: CalendarBoundary.firstDayOfMonth)
		),
		let endDate = Foundation.Calendar.current.date(
			from: DateComponents(year: year, month: CalendarBoundary.december, day: CalendarBoundary.lastDayOfDecember)
		) else {
			return BrowseHansardSitting.Result(sittingDates: [])
		}

		let useCase = browseHansardSitting ?? BrowseHansardSitting(
			repository: SwiftDataHansardRepository(modelContext: modelContext, fetch: fetch)
		)
		return try await useCase.execute(jurisdiction: .federal, from: startDate, through: endDate)
	}

	private func replaceSittingDates(for year: Int, with sittings: [Date]) {
		let splitDates = makeDateComponentSets(from: sittings)
		dates = dates.filter { $0.year != year }
		futureDates = futureDates.filter { $0.year != year }
		dates.formUnion(splitDates.past)
		futureDates.formUnion(splitDates.future)
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
