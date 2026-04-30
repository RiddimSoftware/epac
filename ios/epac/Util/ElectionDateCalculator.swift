//
//  ElectionDateCalculator.swift
//  epac
//
//  Implements the fixed-election-date formula from the Canada Elections Act,
//  section 56.1: "each general election must be held on the third Monday of
//  October in the fourth calendar year following polling day for the last
//  general election."
//

import Foundation

// Source-of-truth for the Canada Elections Act fixed-election-date rule.
// Pure functions — caller passes in dependencies (last election date, "now")
// so the same code is testable for any year boundary without freezing time.
enum ElectionDateCalculator {

	// 45th Canadian general election was held 2025-04-28. Source:
	// Elections Canada (https://www.elections.ca/content.aspx?section=ele).
	// Hard-coded until EPAC-68 ships a structured Elections Canada record;
	// kept as a constant so a writ-issuance follow-up can override it
	// without touching call sites.
	static let last45thGeneralElection: Date = {
		var components = DateComponents()
		components.year = 2025
		components.month = 4
		components.day = 28
		components.hour = 12
		components.timeZone = TimeZone(identifier: "America/Toronto")
		return Calendar(identifier: .gregorian).date(from: components)!
	}()

	// Returns the statutorily mandated date for the *next* general election,
	// given the polling day of the previous one. The rule lives in
	// `nextMandatedDate(after:)` so unit tests can drive it with arbitrary
	// inputs (boundary years, leap years, etc.) without baking in a date.
	static func nextMandatedDate(after previousElection: Date) -> Date {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		let previousYear = calendar.component(.year, from: previousElection)
		let targetYear = previousYear + 4
		return thirdMondayOfOctober(year: targetYear, calendar: calendar)
	}

	// Days remaining between `now` (start-of-day) and the mandated date.
	// Negative values clamp to zero — calling code shows "Election day" or
	// updates to the writ date once an election is called.
	static func daysRemaining(now: Date, mandatedDate: Date) -> Int {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		let startOfNow = calendar.startOfDay(for: now)
		let startOfTarget = calendar.startOfDay(for: mandatedDate)
		let components = calendar.dateComponents([.day], from: startOfNow, to: startOfTarget)
		return max(0, components.day ?? 0)
	}

	// Third Monday of October falls on the 15th–21st depending on the year:
	// step from Oct 1, advance to the first Monday, then add two weeks.
	static func thirdMondayOfOctober(year: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
		var components = DateComponents()
		components.year = year
		components.month = 10
		components.day = 1
		components.hour = 9
		components.timeZone = calendar.timeZone
		guard let october1 = calendar.date(from: components) else {
			fatalError("Could not construct October 1 for year \(year)")
		}
		let weekday = calendar.component(.weekday, from: october1) // Sunday=1, Monday=2
		let daysUntilFirstMonday = (9 - weekday) % 7 // 0 if Oct 1 is Mon, else days to next Mon
		guard let firstMonday = calendar.date(byAdding: .day, value: daysUntilFirstMonday, to: october1),
		      let thirdMonday = calendar.date(byAdding: .day, value: 14, to: firstMonday) else {
			fatalError("Could not derive third Monday of October \(year)")
		}
		return thirdMonday
	}
}
