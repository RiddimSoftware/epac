@testable import epac
import Foundation
import SwiftData
import Testing

// Tests for the pure computed properties of SittingCalendarViewModel — no
// network or SwiftData interaction is required. Fetch/ModelContext are passed
// through async methods, but injected BrowseHansardSitting use cases keep these
// tests deterministic.
@MainActor
struct SittingCalendarViewModelTests {

    // Helpers

    private func dateComponents(year: Int, month: Int, day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func containsYMD(_ components: Set<DateComponents>, year: Int, month: Int, day: Int) -> Bool {
        let expected = dateComponents(year: year, month: month, day: day)
        return components.contains { $0.sameYMD(as: expected) }
    }

    private func makeDependencies() throws -> (ModelContext, Fetch) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
        return (ModelContext(container), Fetch(modelContainer: container))
    }

    // MARK: - sittingDayCount

	@Test func sittingDayCountIncludesPastAndFutureForCurrentYear() {
		let viewModel = SittingCalendarViewModel()
		let year = Calendar.current.component(.year, from: Date())
		viewModel.dates.insert(dateComponents(year: year, month: 4, day: 28))
		viewModel.dates.insert(dateComponents(year: year - 1, month: 12, day: 1))
		viewModel.futureDates.insert(dateComponents(year: year, month: 5, day: 5))

		// Only the two dates in the current year should be counted.
		#expect(viewModel.sittingDayCount == 2)
	}

	@Test func sittingDayCountIsZeroOnEmptyViewModel() {
		let viewModel = SittingCalendarViewModel()
		#expect(viewModel.sittingDayCount == 0)
	}

    // MARK: - upcomingSittingDates

	@Test func upcomingSittingDatesFiltersToWindow() {
		let viewModel = SittingCalendarViewModel()
		let anchor = date(year: 2026, month: 5, day: 1)
		// Inside window
		viewModel.futureDates.insert(dateComponents(year: 2026, month: 5, day: 5))
		viewModel.futureDates.insert(dateComponents(year: 2026, month: 5, day: 28))
		// Outside window (> 30 days from anchor)
		viewModel.futureDates.insert(dateComponents(year: 2026, month: 6, day: 15))

		let result = viewModel.upcomingSittingDates(from: anchor, throughDays: 30)
		#expect(result.count == 2)
	}

	@Test func upcomingSittingDatesReturnsSortedAscending() {
		let viewModel = SittingCalendarViewModel()
		let anchor = date(year: 2026, month: 5, day: 1)
		viewModel.futureDates.insert(dateComponents(year: 2026, month: 5, day: 20))
		viewModel.futureDates.insert(dateComponents(year: 2026, month: 5, day: 10))

		let result = viewModel.upcomingSittingDates(from: anchor, throughDays: 30)
		#expect(result.count == 2)
		#expect(result[0] < result[1])
	}

	@Test func cacheFirstLoadAppliesCachedDatesBeforeDeferredFetchCompletes() async throws {
		let (context, fetch) = try makeDependencies()
		let year = Calendar.current.component(.year, from: Date())
		let cachedDate = date(year: year, month: 1, day: 1)
		let remoteDate = date(year: year, month: 12, day: 2)
		context.insert(SittingCalendar(year: year, sittings: [cachedDate]))
		try context.save()

		let browseUseCase = DeferredBrowseHansardSittingUseCase(
			updatedDates: [year: [remoteDate]],
			delaysMs: [year: 80]
		)
		let viewModel = SittingCalendarViewModel(browseHansardSitting: browseUseCase)

		viewModel.loadSittingCalendarCacheFirst(year, modelContext: context, fetch: fetch)

		#expect(containsYMD(viewModel.sittingDateComponents, year: year, month: 1, day: 1))
		#expect(!containsYMD(viewModel.sittingDateComponents, year: year, month: 12, day: 2))

		try await Task.sleep(for: .milliseconds(120))

		#expect(browseUseCase.calls == 1)
		#expect(!containsYMD(viewModel.sittingDateComponents, year: year, month: 1, day: 1))
		#expect(containsYMD(viewModel.sittingDateComponents, year: year, month: 12, day: 2))
		#expect(!viewModel.loadFailed)
	}

	@Test func cacheFirstLoadSetsLoadFailedWhenDeferredFetchFails() async throws {
		let (context, fetch) = try makeDependencies()
		let year = Calendar.current.component(.year, from: Date())
		let browseUseCase = DeferredBrowseHansardSittingUseCase(
			failingYears: [year],
			delaysMs: [year: 20]
		)
		let viewModel = SittingCalendarViewModel(browseHansardSitting: browseUseCase)

		viewModel.loadSittingCalendarCacheFirst(year, modelContext: context, fetch: fetch)
		#expect(!viewModel.loadFailed)

		try await Task.sleep(for: .milliseconds(60))

		#expect(browseUseCase.calls == 1)
		#expect(viewModel.loadFailed)
	}

	@Test func cacheFirstLoadCancelsStaleDeferredFetchAfterYearChange() async throws {
		let (context, fetch) = try makeDependencies()
		let year = Calendar.current.component(.year, from: Date())
		let previousYear = year - 1
		let staleDate = date(year: year, month: 12, day: 1)
		let currentDate = date(year: previousYear, month: 12, day: 2)
		let browseUseCase = DeferredBrowseHansardSittingUseCase(
			updatedDates: [
				year: [staleDate],
				previousYear: [currentDate]
			],
			delaysMs: [
				year: 80,
				previousYear: 10
			]
		)
		let viewModel = SittingCalendarViewModel(browseHansardSitting: browseUseCase)

		viewModel.loadSittingCalendarCacheFirst(year, modelContext: context, fetch: fetch)
		try await Task.sleep(for: .milliseconds(5))
		viewModel.loadSittingCalendarCacheFirst(previousYear, modelContext: context, fetch: fetch)
		try await Task.sleep(for: .milliseconds(120))

		#expect(browseUseCase.calls == 2)
		#expect(!containsYMD(viewModel.sittingDateComponents, year: year, month: 12, day: 1))
		#expect(containsYMD(viewModel.sittingDateComponents, year: previousYear, month: 12, day: 2))
		#expect(!viewModel.loadFailed)
	}

    @Test func rapidRefreshKeepsNewestCompletedLoadApplied() async throws {
        let (context, fetch) = try makeDependencies()
		let year = Calendar.current.component(.year, from: Date())
		let staleDate = date(year: year, month: 12, day: 1)
		let freshDate = date(year: year, month: 12, day: 2)
		let browseUseCase = DelayedBrowseHansardSittingUseCase(staleDate: staleDate, freshDate: freshDate)
		let viewModel = SittingCalendarViewModel(browseHansardSitting: browseUseCase)
		viewModel.currentYear = year

		let firstRefresh = Task { await viewModel.refresh(modelContext: context, fetch: fetch) }
		try await Task.sleep(for: .milliseconds(10))
		let secondRefresh = Task { await viewModel.refresh(modelContext: context, fetch: fetch) }

        await firstRefresh.value
		await secondRefresh.value

		#expect(browseUseCase.callCount == 2)
		#expect(containsYMD(viewModel.futureDates, year: year, month: 12, day: 2))
		#expect(!containsYMD(viewModel.futureDates, year: year, month: 12, day: 1))
		#expect(!viewModel.loadFailed)
	}

    @Test func refreshPreservesSittingDatesFromOtherYears() async throws {
		let (context, fetch) = try makeDependencies()
		let currentYear = Calendar.current.component(.year, from: Date())
		let previousYear = currentYear - 1
		let refreshedCurrentYearDate = date(year: currentYear, month: 12, day: 1)
		let browseUseCase = SingleYearBrowseHansardSittingUseCase(
			updatedDates: [currentYear: [refreshedCurrentYearDate]]
		)

		let viewModel = SittingCalendarViewModel(browseHansardSitting: browseUseCase)
		viewModel.currentYear = currentYear
		viewModel.dates = [
			dateComponents(year: previousYear, month: 6, day: 10),
			dateComponents(year: currentYear, month: 1, day: 1)
		]

		await viewModel.refresh(modelContext: context, fetch: fetch)

		#expect(viewModel.dates.contains(dateComponents(year: previousYear, month: 6, day: 10)))
		#expect(!viewModel.dates.contains(dateComponents(year: currentYear, month: 1, day: 1)))
		#expect(!viewModel.dates.contains(dateComponents(year: currentYear, month: 12, day: 1)))
		#expect(containsYMD(viewModel.futureDates, year: currentYear, month: 12, day: 1))
		#expect(browseUseCase.calls == 1)
		#expect(!viewModel.loadFailed)
	}
}

@MainActor
private final class DelayedBrowseHansardSittingUseCase: BrowseHansardSittingUseCase {
    private let staleDate: Date
    private let freshDate: Date
    private(set) var callCount = 0
    private let firstCallDelayMs: Int64 = 80
    private let subsequentCallDelayMs: Int64 = 10

    init(staleDate: Date, freshDate: Date) {
        self.staleDate = staleDate
        self.freshDate = freshDate
    }

	func execute(
		jurisdiction: Jurisdiction,
		from startDate: Date,
		through endDate: Date
	) async throws -> BrowseHansardSitting.Result {
		callCount += 1

		if callCount == 1 {
            try await Task.sleep(for: .milliseconds(firstCallDelayMs))
            return BrowseHansardSitting.Result(sittingDates: [staleDate])
        } else {
            try await Task.sleep(for: .milliseconds(subsequentCallDelayMs))
            return BrowseHansardSitting.Result(sittingDates: [freshDate])
        }
    }
}

@MainActor
private final class SingleYearBrowseHansardSittingUseCase: BrowseHansardSittingUseCase {
    private let updatedDates: [Int: [Date]]
    private(set) var calls = 0

    init(updatedDates: [Int: [Date]]) {
        self.updatedDates = updatedDates
    }

	func execute(
		jurisdiction: Jurisdiction,
		from startDate: Date,
		through endDate: Date
	) async throws -> BrowseHansardSitting.Result {
		calls += 1
		guard let year = Calendar.current.dateComponents([.year], from: startDate).year else {
			return BrowseHansardSitting.Result(sittingDates: [])
		}
        return BrowseHansardSitting.Result(sittingDates: updatedDates[year] ?? [])
    }
}

@MainActor
private final class DeferredBrowseHansardSittingUseCase: BrowseHansardSittingUseCase {
	private let updatedDates: [Int: [Date]]
	private let failingYears: Set<Int>
	private let delaysMs: [Int: Int64]
	private(set) var calls = 0

	init(
		updatedDates: [Int: [Date]] = [:],
		failingYears: Set<Int> = [],
		delaysMs: [Int: Int64] = [:]
	) {
		self.updatedDates = updatedDates
		self.failingYears = failingYears
		self.delaysMs = delaysMs
	}

	func execute(
		jurisdiction: Jurisdiction,
		from startDate: Date,
		through endDate: Date
	) async throws -> BrowseHansardSitting.Result {
		calls += 1
		guard let year = Calendar.current.dateComponents([.year], from: startDate).year else {
			return BrowseHansardSitting.Result(sittingDates: [])
		}
		if let delayMs = delaysMs[year] {
			try await Task.sleep(for: .milliseconds(delayMs))
		}
		if failingYears.contains(year) {
			throw DeferredBrowseHansardSittingUseCaseError.failed
		}
		return BrowseHansardSitting.Result(sittingDates: updatedDates[year] ?? [])
	}
}

private enum DeferredBrowseHansardSittingUseCaseError: Error {
	case failed
}
