//
//  GovernmentConsultationsView.swift
//  epac
//

import SwiftUI

// Surfaces open Government of Canada consultations where Canadians can
// provide formal input on legislation, policy, and regulations.
//
// Data source: canada.ca/en/government/system/consultations — the official
// "Consulting with Canadians" database. A live JSON API is not publicly
// documented; this view uses deep-links to the official web portal.
struct GovernmentConsultationsView: View {
	@Environment(\.openURL) private var openURL

	private static let baseURL = "https://www.canada.ca/en/government/system/consultations"

	private let topicLinks: [(label: String, icon: String, color: Color, query: String)] = [
		("Environment & Climate",  "leaf.fill",         .green,   "environment"),
		("Housing & Infrastructure","house.fill",        .blue,    "housing"),
		("Health",                 "heart.fill",        .red,     "health"),
		("Indigenous Peoples",     "person.3.fill",     .orange,  "indigenous"),
		("Finance & Taxation",     "chart.bar.fill",    .indigo,  "finance"),
		("Immigration",            "globe",             .teal,    "immigration"),
		("Agriculture & Food",     "fork.knife",        .brown,   "agriculture"),
		("Justice & Rights",       "scale.3d",          .purple,  "justice"),
	]

	var body: some View {
		List {
			Section {
				headerCard
			}

			Section("Browse Open Consultations") {
				ForEach(topicLinks, id: \.label) { item in
					Button {
						openURL(consultationSearchURL(query: item.query))
					} label: {
						HStack(spacing: 12) {
							Image(systemName: item.icon)
								.foregroundStyle(item.color)
								.frame(width: 28)
								.accessibilityHidden(true)
							Text(item.label)
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

			Section("All Consultations") {
				Button {
					openURL(URL(string: "\(Self.baseURL)/consultationsfinder.html")!)
				} label: {
					HStack(spacing: 12) {
						Image(systemName: "magnifyingglass.circle.fill")
							.foregroundStyle(.blue)
							.frame(width: 28)
							.accessibilityHidden(true)
						VStack(alignment: .leading, spacing: 2) {
							Text("Consultations Finder")
								.font(.subheadline)
								.foregroundStyle(.primary)
							Text("Search all open and closed consultations")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Image(systemName: "arrow.up.right.square")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
				Button {
					openURL(URL(string: "\(Self.baseURL).html")!)
				} label: {
					HStack(spacing: 12) {
						Image(systemName: "list.bullet.rectangle.fill")
							.foregroundStyle(.secondary)
							.frame(width: 28)
							.accessibilityHidden(true)
						Text("Consulting with Canadians")
							.font(.subheadline)
							.foregroundStyle(.primary)
						Spacer()
						Image(systemName: "arrow.up.right.square")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					Text("How consultations work")
						.font(.caption.bold())
					Text("Federal departments consult Canadians when developing major policies, regulations, and legislation. Input is accepted online, by mail, or at in-person sessions. Submissions become part of the public record.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 4)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Consultations")
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sub-views

	private var headerCard: some View {
		HStack(spacing: 12) {
			Image(systemName: "bubble.left.and.text.bubble.right.fill")
				.font(.title2)
				.foregroundStyle(.teal)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 3) {
				Text("Have your say")
					.font(.headline)
				Text("Government departments consult Canadians before making major policy decisions. Open consultations accept public input.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	// MARK: - URL helpers

	private func consultationSearchURL(query: String) -> URL {
		var components = URLComponents(string: "\(Self.baseURL)/consultationsfinder.html")!
		components.queryItems = [URLQueryItem(name: "topic", value: query)]
		return components.url ?? URL(string: Self.baseURL)!
	}
}
