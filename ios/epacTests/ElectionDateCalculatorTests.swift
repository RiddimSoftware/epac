import Testing
import Foundation
@testable import epac

struct ElectionDateCalculatorTests {

	private var torontoCalendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		return calendar
	}

	private func makeDate(year: Int, month: Int, day: Int) -> Date {
		var components = DateComponents()
		components.year = year
		components.month = month
		components.day = day
		components.hour = 12
		components.timeZone = TimeZone(identifier: "America/Toronto")
		return Calendar(identifier: .gregorian).date(from: components)!
	}

	// MARK: - thirdMondayOfOctober — known years

	@Test func thirdMondayOctober2025_isOct20() {
		let date = ElectionDateCalculator.thirdMondayOfOctober(year: 2025, calendar: torontoCalendar)
		let calendar = torontoCalendar
		#expect(calendar.component(.year, from: date) == 2025)
		#expect(calendar.component(.month, from: date) == 10)
		#expect(calendar.component(.day, from: date) == 20)
		#expect(calendar.component(.weekday, from: date) == 2) // Monday
	}

	@Test func thirdMondayOctober2029_isOct15() {
		let date = ElectionDateCalculator.thirdMondayOfOctober(year: 2029, calendar: torontoCalendar)
		let calendar = torontoCalendar
		#expect(calendar.component(.year, from: date) == 2029)
		#expect(calendar.component(.month, from: date) == 10)
		#expect(calendar.component(.day, from: date) == 15)
	}

	@Test func thirdMondayOctober2026_isOct19() {
		let date = ElectionDateCalculator.thirdMondayOfOctober(year: 2026, calendar: torontoCalendar)
		let calendar = torontoCalendar
		#expect(calendar.component(.day, from: date) == 19)
	}

	// October 1 falls on a Monday in 2018 — exercises the "Oct 1 is already
	// Monday" branch of the formula.
	@Test func thirdMondayOctober2018_whenOct1IsMonday_isOct15() {
		let date = ElectionDateCalculator.thirdMondayOfOctober(year: 2018, calendar: torontoCalendar)
		let calendar = torontoCalendar
		#expect(calendar.component(.day, from: date) == 15)
	}

	// MARK: - nextMandatedDate

	@Test func nextMandatedAfter45thElection_isOct15_2029() {
		let next = ElectionDateCalculator.nextMandatedDate(
			after: ElectionDateCalculator.last45thGeneralElection
		)
		let calendar = torontoCalendar
		#expect(calendar.component(.year, from: next) == 2029)
		#expect(calendar.component(.month, from: next) == 10)
		#expect(calendar.component(.day, from: next) == 15)
	}

	@Test func nextMandatedAfter44thElection_isOct20_2025() {
		// 44th general election: 2021-09-20. Statute → third Monday of October 2025.
		let last44th = makeDate(year: 2021, month: 9, day: 20)
		let next = ElectionDateCalculator.nextMandatedDate(after: last44th)
		let calendar = torontoCalendar
		#expect(calendar.component(.year, from: next) == 2025)
		#expect(calendar.component(.month, from: next) == 10)
		#expect(calendar.component(.day, from: next) == 20)
	}

	// MARK: - daysRemaining

	@Test func daysRemaining_today_returnsPositive() {
		let now = makeDate(year: 2026, month: 4, day: 28)
		let target = makeDate(year: 2029, month: 10, day: 15)
		let days = ElectionDateCalculator.daysRemaining(now: now, mandatedDate: target)
		// 2026-04-28 to 2029-10-15: 365*3 (1095) + 6 (May–Apr same start) - check approx
		#expect(days > 1200)
		#expect(days < 1300)
	}

	@Test func daysRemaining_clampsToZero_whenTargetIsPast() {
		let now = makeDate(year: 2030, month: 1, day: 1)
		let target = makeDate(year: 2029, month: 10, day: 15)
		let days = ElectionDateCalculator.daysRemaining(now: now, mandatedDate: target)
		#expect(days == 0)
	}

	@Test func daysRemaining_zero_whenSameDay() {
		let day = makeDate(year: 2029, month: 10, day: 15)
		let days = ElectionDateCalculator.daysRemaining(now: day, mandatedDate: day)
		#expect(days == 0)
	}
}
