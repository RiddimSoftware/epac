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

	/// Groups messages by calendar day (UTC), most recent first.
	private var byDay: [(date: Date, count: Int)] {
		var counts: [Date: Int] = [:]
		let cal = Calendar.current
		for msg in messages {
			let day = cal.startOfDay(for: msg.timestamp)
			counts[day, default: 0] += 1
		}
		return counts
			.sorted { $0.key > $1.key }
			.map { (date: $0.key, count: $0.value) }
	}

	private var mostActiveDay: (date: Date, count: Int)? { byDay.max(by: { $0.count < $1.count }) }

	var body: some View {
		Group {
			if messages.isEmpty {
				ContentUnavailableView {
					Label("No debate records", systemImage: "text.bubble")
				} description: {
					Text("Open sitting days to load debate transcripts for this member.")
				}
			} else {
				List {
					Section {
						summaryCard
					}
					Section("Recent Sitting Days") {
						ForEach(byDay.prefix(50), id: \.date) { entry in
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(entry.date.formatted(date: .long, time: .omitted))
										.font(.subheadline)
									Text("\(entry.count) contribution\(entry.count == 1 ? "" : "s")")
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
		.navigationTitle("Debate Activity")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Summary card

	private var summaryCard: some View {
		VStack(spacing: 12) {
			HStack(spacing: 0) {
				StatPill(value: messages.count, label: "Contributions")
				StatPill(value: byDay.count, label: "Sitting Days")
				if let best = mostActiveDay {
					StatPill(value: best.count, label: "Best Day")
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 8))

			if let best = mostActiveDay {
				HStack {
					Text("Most active:")
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
