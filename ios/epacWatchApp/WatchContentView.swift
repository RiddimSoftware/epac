//
//  WatchContentView.swift
//  epacWatchApp
//

import SwiftUI

struct WatchContentView: View {
	private let snapshot = WatchParliamentSnapshot.read()
	private let contentSpacing: CGFloat = 8
	private let lastVoteLineLimit: Int = 3

	var body: some View {
		VStack(alignment: .leading, spacing: contentSpacing) {
			Label(snapshot.statusText, systemImage: "building.columns.fill")
				.font(.headline)
			if let lastVoteLine = snapshot.lastVoteLine {
				Text(lastVoteLine)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(lastVoteLineLimit)
			} else {
				Text(snapshot.nextSittingText)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.padding()
	}
}

struct WatchParliamentSnapshot {
	let isSittingToday: Bool
	let nextSitting: Date?
	let lastVoteTitle: String
	let lastVoteBill: String
	let lastVoteResult: String
	let lastVoteDate: Date?
	let lastVoteYea: Int
	let lastVoteNay: Int

	var statusText: String {
		isSittingToday ? "Parliament sitting" : "Not sitting"
	}

	var nextSittingText: String {
		guard let nextSitting else { return "Open epac to sync Parliament data" }
		if Calendar.current.isDateInToday(nextSitting) { return "Sitting today" }
		return "Next: \(nextSitting.formatted(date: .abbreviated, time: .omitted))"
	}

	var lastVoteLine: String? {
		guard !lastVoteTitle.isEmpty else { return nil }
		let voteLabel = lastVoteBill.isEmpty ? "Last vote" : "Last vote: \(lastVoteBill)"
		let result = lastVoteResult.isEmpty ? "\(lastVoteYea)-\(lastVoteNay)" : lastVoteResult
		return "\(voteLabel) \(result)"
	}

	static func read() -> WatchParliamentSnapshot {
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
		return WatchParliamentSnapshot(
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
