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
        let vm = SittingCalendarViewModel()
        let year = Calendar.current.component(.year, from: Date())
        vm.dates.insert(dateComponents(year: year, month: 4, day: 28))
        vm.dates.insert(dateComponents(year: year - 1, month: 12, day: 1))
        vm.futureDates.insert(dateComponents(year: year, month: 5, day: 5))

        // Only the two dates in the current year should be counted.
        #expect(vm.sittingDayCount == 2)
    }

    @Test func sittingDayCountIsZeroOnEmptyViewModel() {
        let vm = SittingCalendarViewModel()
        #expect(vm.sittingDayCount == 0)
    }

    // MARK: - upcomingSittingDates

    @Test func upcomingSittingDatesFiltersToWindow() {
        let vm = SittingCalendarViewModel()
        let anchor = date(year: 2026, month: 5, day: 1)
        // Inside window
        vm.futureDates.insert(dateComponents(year: 2026, month: 5, day: 5))
        vm.futureDates.insert(dateComponents(year: 2026, month: 5, day: 28))
        // Outside window (> 30 days from anchor)
        vm.futureDates.insert(dateComponents(year: 2026, month: 6, day: 15))

        let result = vm.upcomingSittingDates(from: anchor, throughDays: 30)
        #expect(result.count == 2)
    }

    @Test func upcomingSittingDatesReturnsSortedAscending() {
        let vm = SittingCalendarViewModel()
        let anchor = date(year: 2026, month: 5, day: 1)
        vm.futureDates.insert(dateComponents(year: 2026, month: 5, day: 20))
        vm.futureDates.insert(dateComponents(year: 2026, month: 5, day: 10))

        let result = vm.upcomingSittingDates(from: anchor, throughDays: 30)
        #expect(result.count == 2)
        #expect(result[0] < result[1])
    }

    @Test func rapidRefreshKeepsNewestCompletedLoadApplied() async throws {
        let (context, fetch) = try makeDependencies()
        let year = Calendar.current.component(.year, from: Date())
        let staleDate = date(year: year, month: 12, day: 1)
        let freshDate = date(year: year, month: 12, day: 2)
        let browseUseCase = DelayedBrowseHansardSittingUseCase(staleDate: staleDate, freshDate: freshDate)
        let vm = SittingCalendarViewModel(browseHansardSitting: browseUseCase)
        vm.currentYear = year

        let firstRefresh = Task { await vm.refresh(modelContext: context, fetch: fetch) }
        try await Task.sleep(for: .milliseconds(10))
        let secondRefresh = Task { await vm.refresh(modelContext: context, fetch: fetch) }

        await firstRefresh.value
        await secondRefresh.value

        #expect(browseUseCase.callCount == 2)
        #expect(containsYMD(vm.futureDates, year: year, month: 12, day: 2))
        #expect(!containsYMD(vm.futureDates, year: year, month: 12, day: 1))
        #expect(!vm.loadFailed)
    }

    @Test func refreshPreservesSittingDatesFromOtherYears() async throws {
        let (context, fetch) = try makeDependencies()
        let currentYear = Calendar.current.component(.year, from: Date())
        let previousYear = currentYear - 1
        let refreshedCurrentYearDate = date(year: currentYear, month: 12, day: 1)
        let browseUseCase = SingleYearBrowseHansardSittingUseCase(updatedDates: [currentYear: [refreshedCurrentYearDate]])

        let vm = SittingCalendarViewModel(browseHansardSitting: browseUseCase)
        vm.currentYear = currentYear
        vm.dates = [
            dateComponents(year: previousYear, month: 6, day: 10),
            dateComponents(year: currentYear, month: 1, day: 1)
        ]

        await vm.refresh(modelContext: context, fetch: fetch)

        #expect(vm.dates.contains(dateComponents(year: previousYear, month: 6, day: 10)))
        #expect(!vm.dates.contains(dateComponents(year: currentYear, month: 1, day: 1)))
        #expect(!vm.dates.contains(dateComponents(year: currentYear, month: 12, day: 1)))
        #expect(containsYMD(vm.futureDates, year: currentYear, month: 12, day: 1))
        #expect(browseUseCase.calls == 1)
        #expect(!vm.loadFailed)
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

    func execute(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> BrowseHansardSitting.Result {
        callCount += 1

        if callCount == 1 {
            try await Task.sleep(for: .milliseconds(firstCallDelayMs))
            return BrowseHansardSitting.Result(sittingDates: [staleDate], sittings: [])
        } else {
            try await Task.sleep(for: .milliseconds(subsequentCallDelayMs))
            return BrowseHansardSitting.Result(sittingDates: [freshDate], sittings: [])
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

    func execute(jurisdiction: Jurisdiction, from: Date, to: Date) async throws -> BrowseHansardSitting.Result {
        calls += 1
        guard let year = Calendar.current.dateComponents([.year], from: from).year else {
            return BrowseHansardSitting.Result(sittingDates: [], sittings: [])
        }
        return BrowseHansardSitting.Result(sittingDates: updatedDates[year] ?? [], sittings: [])
    }
}
