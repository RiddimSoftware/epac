//
//  epacWidgets.swift
//  epac-widget
//

import WidgetKit
import SwiftUI
import Foundation

// MARK: - Shared entry

struct SittingEntry: TimelineEntry {
	let date: Date
	let nextSitting: Date?
	let recentSubjects: [String]
}

// MARK: - Timeline provider (shared)

struct EpacTimelineProvider: TimelineProvider {
	func placeholder(in context: Context) -> SittingEntry {
		SittingEntry(
			date: .now,
			nextSitting: Calendar.current.date(byAdding: .day, value: 2, to: .now),
			recentSubjects: ["Carbon Pricing Act", "Housing Affordability", "Indigenous Affairs"]
		)
	}

	func getSnapshot(in context: Context, completion: @escaping (SittingEntry) -> Void) {
		completion(entry())
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<SittingEntry>) -> Void) {
		// Refresh every 6 hours; the app writes new data via WidgetDataWriter
		// whenever it fetches fresh sitting calendar data.
		let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now
		completion(Timeline(entries: [entry()], policy: .after(nextRefresh)))
	}

	private func entry() -> SittingEntry {
		SittingEntry(
			date: .now,
			nextSitting: WidgetDataReader.nextSitting(),
			recentSubjects: WidgetDataReader.recentSubjects()
		)
	}
}

// Reads from the App Group — mirrors WidgetDataWriter on the app side.
// Constants are intentionally duplicated here rather than shared via a framework:
// the widget extension and the app are separate compilation units and there is
// no shared Swift package in this project. If a third constant ever appears,
// promote these to a shared WidgetDataConstants.swift inside a local Swift package.
private enum WidgetDataReader {
	static let appGroupID = "group.net.dinglebox.cabinetdoor"
	private static let nextSittingKey = "widget.nextSitting"
	private static let recentSubjectsKey = "widget.recentSubjects"

	static func nextSitting() -> Date? {
		guard let interval = UserDefaults(suiteName: appGroupID)?
			.object(forKey: nextSittingKey) as? TimeInterval else { return nil }
		return Date(timeIntervalSince1970: interval)
	}

	static func recentSubjects() -> [String] {
		UserDefaults(suiteName: appGroupID)?.stringArray(forKey: recentSubjectsKey) ?? []
	}
}

// MARK: - Small widget: Next sitting date

struct NextSittingWidget: Widget {
	let kind = "NextSittingWidget"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: EpacTimelineProvider()) { entry in
			NextSittingWidgetView(entry: entry)
				.containerBackground(.fill.tertiary, for: .widget)
		}
		.configurationDisplayName("Next Sitting")
		.description("Shows the next scheduled House of Commons sitting day.")
		.supportedFamilies([.systemSmall])
	}
}

struct NextSittingWidgetView: View {
	let entry: SittingEntry

	var body: some View {
		if let next = entry.nextSitting {
			let daysUntil = Calendar.current.dateComponents([.day], from: .now, to: next).day ?? 0
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Image(systemName: "building.columns.fill")
						.foregroundStyle(.secondary)
					Text("epac")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Text(next.formatted(date: .abbreviated, time: .omitted))
					.font(.headline)
				Text(daysUntil == 0 ? "Today" : daysUntil == 1 ? "Tomorrow" : "In \(daysUntil) days")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
			.padding()
		} else {
			VStack(spacing: 8) {
				Image(systemName: "building.columns.fill")
					.font(.largeTitle)
					.foregroundStyle(.secondary)
				Text("No sitting scheduled")
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

// MARK: - Medium widget: Recent debates

struct RecentDebatesWidget: Widget {
	let kind = "RecentDebatesWidget"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: EpacTimelineProvider()) { entry in
			RecentDebatesWidgetView(entry: entry)
				.containerBackground(.fill.tertiary, for: .widget)
		}
		.configurationDisplayName("Recent Debates")
		.description("Shows the most recent debate subjects from the House of Commons.")
		.supportedFamilies([.systemMedium])
	}
}

struct RecentDebatesWidgetView: View {
	let entry: SittingEntry

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Image(systemName: "building.columns.fill")
					.foregroundStyle(.secondary)
				Text("Recent Debates")
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundStyle(.secondary)
			}
			if entry.recentSubjects.isEmpty {
				Spacer()
				Text("Open epac to load debates")
					.font(.caption)
					.foregroundStyle(.tertiary)
				Spacer()
			} else {
				ForEach(entry.recentSubjects, id: \.self) { subject in
					Text(subject)
						.font(.caption)
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				Spacer()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.padding()
	}
}
