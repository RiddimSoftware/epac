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

	/// Signal WidgetKit to reload all epac widget timelines.
	/// Call after any write so the widget reflects fresh data immediately.
	static func reloadWidgets() {
		WidgetCenter.shared.reloadAllTimelines()
	}
}
