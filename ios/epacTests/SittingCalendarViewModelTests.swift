@testable import epac
import Foundation
import SwiftData
import Testing

// Tests for the pure computed properties of SittingCalendarViewModel — no
// network or SwiftData interaction is required. Fetch/ModelContext are only
// needed in async methods (fetchSittingCalendar, refresh) which are tested
// via integration tests in the existing epacUITests suite.
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

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(SchemaV5.models), configurations: config)
        return ModelContext(container)
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
        let context = try makeContext()
        let year = Calendar.current.component(.year, from: Date())
        let staleDate = date(year: year, month: 12, day: 1)
        let freshDate = date(year: year, month: 12, day: 2)
        let fetcher = DelayedCalendarFetcher(context: context, staleDate: staleDate, freshDate: freshDate)
        let vm = SittingCalendarViewModel()
        vm.currentYear = year

        let firstRefresh = Task { await vm.refresh(modelContext: context, fetch: fetcher) }
        try await Task.sleep(for: .milliseconds(10))
        let secondRefresh = Task { await vm.refresh(modelContext: context, fetch: fetcher) }

        await firstRefresh.value
        await secondRefresh.value

        #expect(fetcher.downloadCallCount == 2)
        #expect(containsYMD(vm.futureDates, year: year, month: 12, day: 2))
        #expect(!containsYMD(vm.futureDates, year: year, month: 12, day: 1))
        #expect(!vm.loadFailed)
    }

    @Test func refreshPreservesSittingDatesFromOtherYears() async throws {
        let context = try makeContext()
        let currentYear = Calendar.current.component(.year, from: Date())
        let previousYear = currentYear - 1
        let refreshedCurrentYearDate = date(year: currentYear, month: 12, day: 1)
        let fetcher = SingleYearCalendarFetcher(context: context, updatedDates: [currentYear: [refreshedCurrentYearDate]])

        let vm = SittingCalendarViewModel()
        vm.currentYear = currentYear
        vm.dates = [
            dateComponents(year: previousYear, month: 6, day: 10),
            dateComponents(year: currentYear, month: 1, day: 1)
        ]

        await vm.refresh(modelContext: context, fetch: fetcher)

        #expect(vm.dates.contains(dateComponents(year: previousYear, month: 6, day: 10)))
        #expect(!vm.dates.contains(dateComponents(year: currentYear, month: 1, day: 1)))
        #expect(!vm.dates.contains(dateComponents(year: currentYear, month: 12, day: 1)))
        #expect(containsYMD(vm.futureDates, year: currentYear, month: 12, day: 1))
        #expect(fetcher.downloadCalls == 1)
        #expect(!vm.loadFailed)
    }
}

@MainActor
private final class DelayedCalendarFetcher: SittingCalendarFetching {
    private let context: ModelContext
    private let staleDate: Date
    private let freshDate: Date
    private(set) var downloadCallCount = 0
    private let firstCallDelayMs: Int64 = 80
    private let subsequentCallDelayMs: Int64 = 10

    init(context: ModelContext, staleDate: Date, freshDate: Date) {
        self.context = context
        self.staleDate = staleDate
        self.freshDate = freshDate
    }

    nonisolated func downloadSittingCalendar(_ year: Int) async throws {
        let callNumber = await MainActor.run {
            downloadCallCount += 1
            return downloadCallCount
        }

        if callNumber == 1 {
            try await Task.sleep(for: .milliseconds(firstCallDelayMs))
            await MainActor.run { upsertCalendar(year: year, sittings: [staleDate]) }
        } else {
            try await Task.sleep(for: .milliseconds(subsequentCallDelayMs))
            await MainActor.run { upsertCalendar(year: year, sittings: [freshDate]) }
        }
    }

    private func upsertCalendar(year: Int, sittings: [Date]) {
        let descriptor = FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })
        if let existing = try? context.fetch(descriptor).first {
            existing.sittings = sittings
        } else {
            context.insert(SittingCalendar(year: year, sittings: sittings))
        }
        try? context.save()
    }
}

@MainActor
private final class SingleYearCalendarFetcher: SittingCalendarFetching {
    private let context: ModelContext
    private let updatedDates: [Int: [Date]]
    private(set) var downloadCalls = 0

    init(context: ModelContext, updatedDates: [Int: [Date]]) {
        self.context = context
        self.updatedDates = updatedDates
    }

    nonisolated func downloadSittingCalendar(_ year: Int) async throws {
        await MainActor.run {
            downloadCalls += 1
        }
        await MainActor.run {
            upsertCalendar(context: context, year: year, sittings: updatedDates[year] ?? [])
        }
    }
}

private func upsertCalendar(context: ModelContext, year: Int, sittings: [Date]) {
    let descriptor = FetchDescriptor<SittingCalendar>(predicate: #Predicate { $0.year == year })
    if let existing = try? context.fetch(descriptor).first {
        existing.sittings = sittings
    } else {
        context.insert(SittingCalendar(year: year, sittings: sittings))
    }
    try? context.save()
}
