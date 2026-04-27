//
//  RidingElectionHistoryView.swift
//  epac
//

import SwiftUI
import SwiftData

// Shows past and present electoral context for a riding.
// Data sources:
//   - Local: ParliamentMember.riding, province, party (current holder)
//   - Local: Constituency model (riding name, province, party)
//   - External links: Elections Canada (official results), openparliament.ca (context)
//
// We don't store historical election results locally; this view surfaces
// what we know and provides verified deep-links for the rest.
struct RidingElectionHistoryView: View {
	let member: ParliamentMember

	@Environment(\.openURL) private var openURL
	@Query private var constituencies: [Constituency]

	private var constituency: Constituency? {
		constituencies.first { $0.name.localizedCaseInsensitiveContains(member.riding) ||
		                       member.riding.localizedCaseInsensitiveContains($0.name) }
	}

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
		HStack(spacing: 12) {
			Circle()
				.fill(Color(uiColor: member.party.colour))
				.frame(width: 14, height: 14)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 3) {
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
		.padding(.vertical, 4)
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
			HStack(spacing: 12) {
				Image(systemName: systemImage)
					.foregroundStyle(color)
					.frame(width: 28)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
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
		// openparliament.ca riding search
		let ridingSlug = member.riding
			.lowercased()
			.replacingOccurrences(of: " ", with: "-")
			.replacingOccurrences(of: "–", with: "-")
			.replacingOccurrences(of: "--", with: "-")
		return URL(string: "https://openparliament.ca/politicians/?riding=\(ridingSlug)") ??
		       URL(string: "https://openparliament.ca")!
	}
}
