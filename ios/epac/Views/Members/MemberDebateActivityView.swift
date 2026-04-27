//
//  MemberDebateActivityView.swift
//  epac
//

import SwiftUI
import SwiftData

// Shows how often a member speaks in the House and what topics they address.
// Data source: SpeechMessage records already in SwiftData from the Hansard
// fetch pipeline. When no speeches are loaded yet, auto-fetches the most
// recent sitting days from the already-downloaded SittingCalendar so the
// user does not have to navigate the calendar manually.
struct MemberDebateActivityView: View {
	let member: ParliamentMember

	@Environment(\.modelContext) private var modelContext
	@EnvironmentObject private var fetch: Fetch
	@Query private var messages: [SpeechMessage]

	@State private var isLoading = false
	@State private var loadedCount = 0
	/// True once the initial auto-load has been attempted (even if it returned no results).
	/// Prevents the emptyView from flashing before the first load begins.
	@State private var hasAttemptedLoad = false

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
			if messages.isEmpty && (isLoading || !hasAttemptedLoad) {
				loadingView
			} else if messages.isEmpty {
				emptyView
			} else {
				resultsList(stats: stats)
			}
		}
		.navigationTitle(NSLocalizedString("debate.navTitle", comment: ""))
		.navigationBarTitleDisplayMode(.inline)
		.task {
			// Auto-load recent sittings on first appearance if no speeches are cached.
			if messages.isEmpty && !isLoading {
				await loadRecentSittings()
			}
			hasAttemptedLoad = true
		}
	}

	// MARK: - Sub-views

	private var loadingView: some View {
		VStack(spacing: 16) {
			ProgressView()
			Text(loadedCount == 0
				 ? NSLocalizedString("debate.loading.start", comment: "")
				 : String(format: NSLocalizedString("debate.loading.progress", comment: ""), loadedCount))
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var emptyView: some View {
		VStack(spacing: 16) {
			Image(systemName: "text.bubble")
				.font(.system(size: 48, weight: .thin))
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			Text(NSLocalizedString("debate.empty.title", comment: ""))
				.font(.headline)
			Text(NSLocalizedString("debate.empty.noSpeeches", comment: ""))
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Button(NSLocalizedString("debate.empty.loadMore", comment: "")) {
				Task { await loadRecentSittings(limit: 60) }
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
			.disabled(isLoading)
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private func resultsList(stats: DayStats) -> some View {
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
							Text(String(format: NSLocalizedString("debate.contributionCount", comment: ""), entry.count))
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

	// MARK: - Data loading

	/// Fetches the most recent `limit` sitting days from the already-downloaded
	/// SittingCalendar and triggers Hansard downloads for each. Speech messages
	/// then appear via the @Query automatically.
	private func loadRecentSittings(limit: Int = 30) async {
		guard !isLoading else { return }
		isLoading = true
		loadedCount = 0
		defer { isLoading = false }

		let calendars = (try? modelContext.fetch(FetchDescriptor<SittingCalendar>())) ?? []
		let today = Date()
		let recentDates = calendars
			.flatMap { $0.sittings }
			.filter { $0 <= today }
			.sorted(by: >)
			.prefix(limit)

		// Only fetch sittings not already in SwiftData.
		let loaded = Set((try? modelContext.fetch(FetchDescriptor<Hansard>()).map { $0.date }) ?? [])

		for date in recentDates where !loaded.contains(date) {
			try? await fetch.downloadHansard(date)
			loadedCount += 1
		}
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
