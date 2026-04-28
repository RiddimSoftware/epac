@testable import epac
import Foundation
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
}
