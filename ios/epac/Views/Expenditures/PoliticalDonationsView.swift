//
//  PoliticalDonationsView.swift
//  epac
//

import SwiftUI

// Shows political financing information for Canada's federal parties.
// Data: Elections Canada public disclosures (elections.ca/fin).
//
// Contribution limits are set annually by Elections Canada under the
// Canada Elections Act. The 2025 limits are indexed to inflation.
// Source: https://www.elections.ca/content.aspx?section=fin&document=ecfin_limits
struct PoliticalDonationsView: View {
	@Environment(\.openURL) private var openURL

	// 2025 contribution limits (indexed annually to CPI)
	private static let partyLimit = 1_750
	private static let combinedAssociationLimit = 1_750

	private let parties: [(Party, String)] = [
		(.liberal,       "Liberal Party of Canada"),
		(.conservative,  "Conservative Party of Canada"),
		(.newdemocratic, "New Democratic Party"),
		(.bloc,          "Bloc Québécois"),
		(.green,         "Green Party of Canada"),
	]

	var body: some View {
		List {
			Section {
				headerCard
			}

			Section("Annual Contribution Limits (2025)") {
				limitRow(
					label: "Per registered party",
					amount: Self.partyLimit,
					note: "Includes donations to riding associations and candidates"
				)
				limitRow(
					label: "Per candidate (election year)",
					amount: Self.combinedAssociationLimit,
					note: "Combined limit for associations and nomination contestants"
				)
			}

			Section("Party Financial Disclosures") {
				ForEach(parties, id: \.0) { party, fullName in
					partyRow(party: party, fullName: fullName)
				}
			}

			Section("Search & Investigate") {
				searchRow(
					title: "Search contributions",
					subtitle: "Find donors and recipients on Elections Canada",
					icon: "magnifyingglass.circle.fill",
					color: .blue,
					url: "https://www.elections.ca/WPAPPS/WPF/EN/PF/SearchContributions"
				)
				searchRow(
					title: "Annual financial returns",
					subtitle: "View all registered party returns by year",
					icon: "doc.text.magnifyingglass",
					color: .indigo,
					url: "https://www.elections.ca/fin/pol-part/pol_part-fra_1.xls"
				)
				searchRow(
					title: "All political financing",
					subtitle: "Full Elections Canada political financing portal",
					icon: "building.columns.fill",
					color: .secondary,
					url: "https://www.elections.ca/content.aspx?section=fin"
				)
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					Text("About political financing")
						.font(.caption.bold())
					Text("Canada bans corporate and union donations to federal parties. Only Canadian citizens and permanent residents may donate, up to the indexed annual limits. All donations above $200 are publicly disclosed.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 4)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Political Donations")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private var headerCard: some View {
		HStack(spacing: 12) {
			Image(systemName: "dollarsign.circle.fill")
				.font(.title2)
				.foregroundStyle(.orange)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 3) {
				Text("Who funds Canada's parties?")
					.font(.headline)
				Text("Donations are publicly disclosed by Elections Canada under the Canada Elections Act.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private func limitRow(label: String, amount: Int, note: String) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(label)
					.font(.subheadline)
				Text(note)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Text(amount, format: .currency(code: "CAD").precision(.fractionLength(0)))
				.font(.headline.monospacedDigit())
				.foregroundStyle(.orange)
		}
		.padding(.vertical, 2)
	}

	private func partyRow(party: Party, fullName: String) -> some View {
		Button {
			if let url = partyURL(party) { openURL(url) }
		} label: {
			HStack(spacing: 12) {
				Circle()
					.fill(Color(uiColor: party.colour))
					.frame(width: 12, height: 12)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text(fullName)
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Annual returns & spending on Elections Canada")
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

	private func searchRow(title: String, subtitle: String, icon: String, color: Color, url: String) -> some View {
		Button {
			if let u = URL(string: url) { openURL(u) }
		} label: {
			HStack(spacing: 12) {
				Image(systemName: icon)
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

	private func partyURL(_ party: Party) -> URL? {
		// Elections Canada party financial returns, keyed by party code
		let codes: [Party: String] = [
			.liberal:       "lib",
			.conservative:  "con",
			.newdemocratic: "ndp",
			.bloc:          "bq",
			.green:         "grn",
		]
		guard let code = codes[party] else { return nil }
		return URL(string: "https://www.elections.ca/fin/pol-part/pol_part-fra.aspx?lang=e&id=\(code)")
	}
}
