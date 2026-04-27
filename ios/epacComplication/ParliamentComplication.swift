//
//  ParliamentComplication.swift
//  epacComplication
//

import SwiftUI
import WidgetKit

struct ParliamentEntry: TimelineEntry {
	let date: Date
	let isSittingToday: Bool
	let nextSitting: Date?
	let lastVoteTitle: String
	let lastVoteBill: String
	let lastVoteResult: String
	let lastVoteDate: Date?
	let lastVoteYea: Int
	let lastVoteNay: Int

	var refreshInterval: Date {
		let calendar = Calendar.current
		if isSittingToday {
			return calendar.date(byAdding: .hour, value: 1, to: date) ?? date
		}
		if let nextSitting {
			let nextSittingRefresh = calendar.date(
				byAdding: .hour,
				value: 1,
				to: calendar.startOfDay(for: nextSitting)
			)
			if let nextSittingRefresh, nextSittingRefresh > date {
				return min(nextSittingRefresh, calendar.date(byAdding: .day, value: 1, to: date) ?? nextSittingRefresh)
			}
		}
		return calendar.date(byAdding: .day, value: 1, to: date) ?? date
	}

	var statusText: String {
		isSittingToday ? "Sitting" : "Not sitting"
	}

	var inlineText: String {
		if isSittingToday {
			return "Parliament sitting"
		}
		guard let nextSitting else { return "Parliament status unavailable" }
		return "Not sitting - Next: \(nextSitting.formatted(date: .abbreviated, time: .omitted))"
	}

	var rectangularText: String {
		let statusPrefix = "House of Commons - \(statusText)"
		if !lastVoteBill.isEmpty || !lastVoteTitle.isEmpty {
			let label = lastVoteBill.isEmpty ? "Last vote" : "Last vote: \(lastVoteBill)"
			let result = lastVoteResult.isEmpty ? "\(lastVoteYea)-\(lastVoteNay)" : lastVoteResult
			return "\(statusPrefix)\n\(label) \(result)"
		}
		return statusPrefix
	}
}

struct ParliamentProvider: TimelineProvider {
	func placeholder(in context: Context) -> ParliamentEntry {
		ParliamentEntry(
			date: .now,
			isSittingToday: true,
			nextSitting: .now,
			lastVoteTitle: "Affordable Housing Act",
			lastVoteBill: "C-50",
			lastVoteResult: "Passed",
			lastVoteDate: .now,
			lastVoteYea: 174,
			lastVoteNay: 149
		)
	}

	func getSnapshot(in context: Context, completion: @escaping (ParliamentEntry) -> Void) {
		completion(readEntry())
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<ParliamentEntry>) -> Void) {
		let entry = readEntry()
		completion(Timeline(entries: [entry], policy: .after(entry.refreshInterval)))
	}

	private func readEntry() -> ParliamentEntry {
		let defaults = UserDefaults(suiteName: "group.net.dinglebox.cabinetdoor")
		func date(forKey key: String) -> Date? {
			guard let interval = defaults?.object(forKey: key) as? TimeInterval else { return nil }
			return Date(timeIntervalSince1970: interval)
		}
		let calendar = Calendar.current
		let nextSitting = date(forKey: "widget.parliament.nextSittingDate")
		let statusUpdatedAt = date(forKey: "widget.parliament.statusUpdatedAt")
		let storedSittingToday = defaults?.bool(forKey: "widget.parliament.isSittingToday") ?? false
		let storedStatusIsCurrent = statusUpdatedAt.map { calendar.isDateInToday($0) } ?? false
		let inferredSittingToday = nextSitting.map { calendar.isDateInToday($0) } ?? false
		return ParliamentEntry(
			date: .now,
			isSittingToday: (storedSittingToday && storedStatusIsCurrent) || inferredSittingToday,
			nextSitting: nextSitting,
			lastVoteTitle: defaults?.string(forKey: "widget.parliament.lastVoteTitle") ?? "",
			lastVoteBill: defaults?.string(forKey: "widget.parliament.lastVoteBill") ?? "",
			lastVoteResult: defaults?.string(forKey: "widget.parliament.lastVoteResult") ?? "",
			lastVoteDate: date(forKey: "widget.parliament.lastVoteDate"),
			lastVoteYea: defaults?.integer(forKey: "widget.parliament.lastVoteYea") ?? 0,
			lastVoteNay: defaults?.integer(forKey: "widget.parliament.lastVoteNay") ?? 0
		)
	}
}

struct ParliamentComplication: Widget {
	let kind = "ParliamentComplication"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: ParliamentProvider()) { entry in
			ParliamentComplicationView(entry: entry)
				.widgetURL(URL(string: "cabinetdoor://sitting/\(Self.todayPath)")!)
				.containerBackground(.fill.tertiary, for: .widget)
		}
		.configurationDisplayName("Parliament Today")
		.description("Shows whether Parliament is sitting and the latest recorded vote.")
		.supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
	}

	private static var todayPath: String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_CA_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.string(from: .now)
	}
}

struct ParliamentComplicationView: View {
	let entry: ParliamentEntry
	@Environment(\.widgetFamily) private var family

	var body: some View {
		switch family {
		case .accessoryCircular:
			VStack(spacing: 2) {
				Image(systemName: "building.columns.fill")
				Text(entry.isSittingToday ? "Sit" : "Off")
					.font(.caption2)
			}
			.widgetAccentable()
			.accessibilityLabel("House of Commons \(entry.statusText)")
		case .accessoryCorner:
			Text(entry.statusText)
				.widgetCurvesContent()
				.widgetLabel {
					Image(systemName: "building.columns.fill")
				}
				.accessibilityLabel("House of Commons \(entry.statusText)")
		case .accessoryRectangular:
			VStack(alignment: .leading, spacing: 2) {
				Label("House of Commons", systemImage: "building.columns.fill")
					.font(.caption2)
				Text(entry.rectangularText)
					.font(.caption)
					.lineLimit(2)
			}
			.accessibilityElement(children: .combine)
		case .accessoryInline:
			Label(entry.inlineText, systemImage: "building.columns.fill")
		default:
			Label(entry.statusText, systemImage: "building.columns.fill")
		}
	}
}
