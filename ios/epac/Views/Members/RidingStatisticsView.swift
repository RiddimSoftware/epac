//
//  RidingStatisticsView.swift
//  epac
//

import SwiftUI
import SwiftData

// Shows socioeconomic statistics for a federal electoral district.
// Primary data source: Statistics Canada 2021 Census Profile for
// Federal Electoral Districts (Table 98-401-X2021014).
//
// The app does not cache census data locally (large dataset, infrequent
// updates). Instead it deep-links to the authoritative sources so users
// always see current data.
struct RidingStatisticsView: View {
	let member: ParliamentMember
	@Environment(\.openURL) private var openURL

	private static let statcanBaseURL = "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof"
	private static let cmhcBaseURL    = "https://www.cmhc-schl.gc.ca"

	private let statCategories: [(label: String, icon: String, color: Color)] = [
		("Population & Age",      "person.2.fill",      .blue),
		("Income & Employment",   "banknote.fill",      .green),
		("Housing",               "house.fill",         .orange),
		("Education",             "graduationcap.fill", .purple),
		("Immigration & Diversity","globe",             .teal),
	]

	var body: some View {
		List {
			Section {
				ridingContextCard
			}

			Section("2021 Census Data") {
				statCanSearchRow
				ForEach(statCategories, id: \.label) { cat in
					Button {
						openURL(statCanURL(topic: cat.label))
					} label: {
						HStack(spacing: 12) {
							Image(systemName: cat.icon)
								.foregroundStyle(cat.color)
								.frame(width: 28)
								.accessibilityHidden(true)
							Text(cat.label)
								.font(.subheadline)
								.foregroundStyle(.primary)
							Spacer()
							Image(systemName: "arrow.up.right.square")
								.font(.caption)
								.foregroundStyle(.tertiary)
						}
					}
				}
			}

			Section("Housing Market") {
				cmhcRow
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					Text("About this data")
						.font(.caption.bold())
					Text("Statistics Canada releases riding-level census profiles after each census (most recent: 2021). Data covers population, age, household income, housing costs, education, and immigration. CMHC publishes housing market data by metropolitan area.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 4)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Riding Statistics")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private var ridingContextCard: some View {
		HStack(spacing: 12) {
			Circle()
				.fill(Color.party(member.party))
				.frame(width: 12, height: 12)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 3) {
				Text(member.riding)
					.font(.headline)
				Text("\(member.province.rawValue) · \(member.party.fullName)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private var statCanSearchRow: some View {
		Button {
			openURL(statCanSearchURL())
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "magnifyingglass.circle.fill")
					.foregroundStyle(.blue)
					.frame(width: 28)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text("Find \(member.riding) on Statistics Canada")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("2021 Census Community Profiles · Federal Electoral Districts")
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

	private var cmhcRow: some View {
		Button {
			openURL(cmhcURL())
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "building.2.fill")
					.foregroundStyle(.orange)
					.frame(width: 28)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text("CMHC Housing Data")
						.font(.subheadline)
						.foregroundStyle(.primary)
					Text("Rental vacancy rates, average rents, and starts for \(member.province.rawValue)")
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

	private func statCanSearchURL() -> URL {
		// Search by riding name in the FED community profiles
		var components = URLComponents(string: "\(Self.statcanBaseURL)/search-recherche/lst/page.cfm")!
		components.queryItems = [
			URLQueryItem(name: "Lang", value: "E"),
			URLQueryItem(name: "type", value: "0"),
			URLQueryItem(name: "SurveyID", value: "1178"),
			URLQueryItem(name: "keyword", value: member.riding),
		]
		return components.url ?? URL(string: Self.statcanBaseURL)!
	}

	private func statCanURL(topic: String) -> URL {
		// Topic-filtered view falls back to the search page since topic
		// codes are not stored locally — user can navigate from search.
		statCanSearchURL()
	}

	private func cmhcURL() -> URL {
		// CMHC housing market information centre, province-level
		let province = member.province.rawValue
			.lowercased()
			.replacingOccurrences(of: " ", with: "-")
		return URL(string: "\(Self.cmhcBaseURL)/en/housing-observer-online")
		    ?? URL(string: Self.cmhcBaseURL)!
	}
}
