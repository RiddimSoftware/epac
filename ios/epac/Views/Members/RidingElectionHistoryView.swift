//
//  RidingElectionHistoryView.swift
//  epac
//

import SwiftUI

private enum Layout {
	static let rowSpacing: CGFloat = 12
	static let partyDotSize: CGFloat = 14
	static let currentSeatTextSpacing: CGFloat = 3
	static let linkIconWidth: CGFloat = 28
}

// Shows past and present electoral context for a riding.
// Data sources:
//   - Local: ParliamentMember.riding, province, party (current holder)
//   - External links: Elections Canada (official results), openparliament.ca (context)
//
// We don't store historical election results locally; this view surfaces
// what we know and provides verified deep-links for the rest.
struct RidingElectionHistoryView: View {
	let member: ParliamentMember

	@Environment(\.openURL) private var openURL

	var body: some View {
		List {
			Section("Current Seat") {
				currentSeatRow
			}

			Section("Historical Results") {
				externalLinkRow(
					title: "Elections Canada",
					subtitle: "Official results for every federal election",
					systemImage: "checkmark.seal.fill",
					color: .red,
					url: electionsCanadaURL
				)
				externalLinkRow(
					title: "openparliament.ca",
					subtitle: "Bills, debates, and votes for this riding",
					systemImage: "building.columns.fill",
					color: .blue,
					url: openParliamentURL
				)
			}

			Section {
				Text("Historical vote tallies and margin-of-victory data are published by Elections Canada after each election. Tap \"Elections Canada\" above to access the full results for \(member.riding).")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Riding History")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private var currentSeatRow: some View {
		HStack(spacing: Layout.rowSpacing) {
			Circle()
				.fill(Color.party(member.party))
				.frame(width: Layout.partyDotSize, height: Layout.partyDotSize)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: Layout.currentSeatTextSpacing) {
				Text(member.name)
					.font(.headline)
				Text(member.party.fullName)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Text("\(member.riding) · \(member.province.rawValue)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, EpacSpacing.xs)
	}

	private func externalLinkRow(
		title: String,
		subtitle: String,
		systemImage: String,
		color: Color,
		url: URL
	) -> some View {
		Button {
			openURL(url)
		} label: {
			HStack(spacing: Layout.rowSpacing) {
				Image(systemName: systemImage)
					.foregroundStyle(color)
					.frame(width: Layout.linkIconWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
					Text(title)
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "arrow.up.right.square")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}

	// MARK: - URLs

	private var electionsCanadaURL: URL {
		// Elections Canada search by electoral district name
		var components = URLComponents(string: "https://www.elections.ca/WPAPPS/WPF/EN/EDT/SearchByName")!
		components.queryItems = [URLQueryItem(name: "strSearch", value: member.riding)]
		return components.url ?? URL(string: "https://www.elections.ca")!
	}

	private var openParliamentURL: URL {
		// openparliament.ca riding search.
		// Canadian riding names use em dashes (—, U+2014) as word separators and may
		// contain accented characters or apostrophes. Normalise to ASCII hyphens first,
		// then percent-encode any remaining characters so URL(string:) never returns nil.
		let slug = member.riding
			.lowercased()
			.replacingOccurrences(of: "—", with: "-")   // em dash (U+2014) — most common
			.replacingOccurrences(of: "–", with: "-")   // en dash (U+2013)
			.replacingOccurrences(of: " ", with: "-")
			.replacingOccurrences(of: "'", with: "")     // apostrophe (e.g. "Saint John's")
			.replacingOccurrences(of: "--", with: "-")   // collapse double-hyphens from above
			.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
		return URL(string: "https://openparliament.ca/politicians/?riding=\(slug)") ??
		       URL(string: "https://openparliament.ca")!
	}
}
