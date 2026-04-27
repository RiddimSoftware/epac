//
//  MemberDebateActivityView.swift
//  epac
//

import SwiftUI
import SwiftData

// Shows how often a member speaks in the House and what topics they address.
// Data source: SpeechMessage records already in SwiftData from the Hansard
// fetch pipeline. No additional API calls required.
struct MemberDebateActivityView: View {
	let member: ParliamentMember

	@Query private var messages: [SpeechMessage]

	init(member: ParliamentMember) {
		self.member = member
		let firstName = member.firstName
		let lastName = member.lastName
		let pred = #Predicate<SpeechMessage> { msg in
			msg.firstName == firstName && msg.lastName == lastName
		}
		var descriptor = FetchDescriptor<SpeechMessage>(predicate: pred, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
		descriptor.fetchLimit = 500
		_messages = Query(descriptor)
	}

	// MARK: - Derived stats

	/// Single-pass computation: builds the by-day list and locates the most-active
	/// day in the same dictionary traversal, avoiding a second `.max` pass.
	private struct DayStats {
		let byDay: [(date: Date, count: Int)]
		let mostActiveDay: (date: Date, count: Int)?
	}

	private var dayStats: DayStats {
		var counts: [Date: Int] = [:]
		let cal = Calendar.current
		for msg in messages {
			let day = cal.startOfDay(for: msg.timestamp)
			counts[day, default: 0] += 1
		}
		var maxCount = 0
		var maxDate: Date?
		let sorted = counts.sorted { $0.key > $1.key }.map { entry -> (date: Date, count: Int) in
			if entry.value > maxCount { maxCount = entry.value; maxDate = entry.key }
			return (date: entry.key, count: entry.value)
		}
		let best = maxDate.map { (date: $0, count: maxCount) }
		return DayStats(byDay: sorted, mostActiveDay: best)
	}

	var body: some View {
		let stats = dayStats
		Group {
			if messages.isEmpty {
				ContentUnavailableView {
					Label(NSLocalizedString("debate.empty.title", comment: ""), systemImage: "text.bubble")
				} description: {
					Text(NSLocalizedString("debate.empty.description", comment: ""))
				}
			} else {
				List {
					Section {
						summaryCard(stats: stats)
					}
					Section(NSLocalizedString("debate.recentSittingDays", comment: "")) {
						ForEach(stats.byDay.prefix(50), id: \.date) { entry in
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(entry.date.formatted(date: .long, time: .omitted))
										.font(.subheadline)
									Text(String.localizedStringWithFormat(
										NSLocalizedString("debate.contributionCount", comment: ""),
										entry.count))
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								Spacer()
								Text("\(entry.count)")
									.font(.headline.monospacedDigit())
									.foregroundStyle(Color.accentColor)
							}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle(NSLocalizedString("debate.navTitle", comment: ""))
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Summary card

	private func summaryCard(stats: DayStats) -> some View {
		VStack(spacing: 12) {
			HStack(spacing: 0) {
				StatPill(value: messages.count, label: NSLocalizedString("debate.stat.contributions", comment: ""))
				StatPill(value: stats.byDay.count, label: NSLocalizedString("debate.stat.sittingDays", comment: ""))
				if let best = stats.mostActiveDay {
					StatPill(value: best.count, label: NSLocalizedString("debate.stat.bestDay", comment: ""))
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 8))

			if let best = stats.mostActiveDay {
				HStack {
					Text(NSLocalizedString("debate.mostActive", comment: ""))
						.font(.caption)
						.foregroundStyle(.secondary)
					Text(best.date.formatted(date: .abbreviated, time: .omitted))
						.font(.caption.bold())
					Spacer()
				}
			}
		}
		.padding(.vertical, 4)
	}
}

private struct StatPill: View {
	let value: Int
	let label: String

	var body: some View {
		VStack(spacing: 2) {
			Text("\(value)")
				.font(.title3.bold().monospacedDigit())
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 8)
		.background(value > 0 ? Color.accentColor.opacity(0.07) : Color.clear)
	}
}
