//
//  WidgetDataWriter.swift
//  epac
//

import Foundation
import WidgetKit

// Writes sitting data into the shared App Group so the home-screen widget
// can read it without launching the full app.
//
// The App Group must be enabled in Xcode → Signing & Capabilities for both
// the epac target and the epac-widget target:
//   Group: group.net.dinglebox.cabinetdoor
enum WidgetDataWriter {
	static let appGroupID = "group.net.dinglebox.cabinetdoor"

	private static var defaults: UserDefaults? {
		UserDefaults(suiteName: appGroupID)
	}

	// Keys
	private static let nextSittingKey = "widget.nextSitting"
	private static let recentSubjectsKey = "widget.recentSubjects"
	private static let isSittingTodayKey = "widget.parliament.isSittingToday"
	private static let nextSittingDateKey = "widget.parliament.nextSittingDate"
	private static let statusUpdatedAtKey = "widget.parliament.statusUpdatedAt"
	private static let lastVoteTitleKey = "widget.parliament.lastVoteTitle"
	private static let lastVoteBillKey = "widget.parliament.lastVoteBill"
	private static let lastVoteResultKey = "widget.parliament.lastVoteResult"
	private static let lastVoteDateKey = "widget.parliament.lastVoteDate"
	private static let lastVoteYeaKey = "widget.parliament.lastVoteYea"
	private static let lastVoteNayKey = "widget.parliament.lastVoteNay"

	/// Write the next scheduled sitting date so the small widget can show it.
	static func writeNextSitting(_ date: Date?) {
		if let date {
			defaults?.set(date.timeIntervalSince1970, forKey: nextSittingKey)
		} else {
			defaults?.removeObject(forKey: nextSittingKey)
		}
	}

	/// Write up to 3 recent subject titles for the medium widget.
	static func writeRecentSubjects(_ titles: [String]) {
		defaults?.set(Array(titles.prefix(3)), forKey: recentSubjectsKey)
	}

	/// Write the compact state used by watchOS complications.
	static func writeParliamentStatus(sittingDates: [Date], today: Date = .now) {
		let calendar = Calendar.current
		let startOfToday = calendar.startOfDay(for: today)
		let sortedSittings = sittingDates
			.map { calendar.startOfDay(for: $0) }
			.sorted()
		let isSittingToday = sortedSittings.contains(startOfToday)
		let nextSitting = sortedSittings.first { $0 >= startOfToday }

		defaults?.set(isSittingToday, forKey: isSittingTodayKey)
		if let nextSitting {
			defaults?.set(nextSitting.timeIntervalSince1970, forKey: nextSittingDateKey)
		} else {
			defaults?.removeObject(forKey: nextSittingDateKey)
		}
		defaults?.set(Date().timeIntervalSince1970, forKey: statusUpdatedAtKey)
	}

	static func writeLastVote(
		title: String,
		billNumber: String,
		result: String,
		date: Date,
		yea: Int,
		nay: Int
	) {
		defaults?.set(title, forKey: lastVoteTitleKey)
		defaults?.set(billNumber, forKey: lastVoteBillKey)
		defaults?.set(result, forKey: lastVoteResultKey)
		defaults?.set(date.timeIntervalSince1970, forKey: lastVoteDateKey)
		defaults?.set(yea, forKey: lastVoteYeaKey)
		defaults?.set(nay, forKey: lastVoteNayKey)
	}

	/// Signal WidgetKit to reload all epac widget timelines.
	/// Call after any write so the widget reflects fresh data immediately.
	static func reloadWidgets() {
		WidgetCenter.shared.reloadAllTimelines()
	}
}
