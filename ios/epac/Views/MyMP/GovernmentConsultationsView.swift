//
//  GovernmentConsultationsView.swift
//  epac
//

import SwiftUI

// Surfaces open Government of Canada consultations where Canadians can
// provide formal input on legislation, policy, and regulations.
//
// Data source: canada.ca/en/government/system/consultations — the official
// "Consulting with Canadians" database.
//
// Note: canada.ca's Consultations Finder applies topic filtering client-side;
// deep-linking with ?topic= parameters does not filter results. All topic
// rows therefore open the main Finder where the user can filter interactively.
struct GovernmentConsultationsView: View {
	@Environment(\.openURL) private var openURL

	private static let finderURL = URL(string:
		"https://www.canada.ca/en/government/system/consultations/consultationsfinder.html")!
	private static let portalURL = URL(string:
		"https://www.canada.ca/en/government/system/consultations.html")!

	private struct TopicItem: Identifiable {
		let id: String      // stable, unique key
		let label: String
		let icon: String
		let color: Color
	}

	private let topics: [TopicItem] = [
		TopicItem(id: "environment",  label: NSLocalizedString("consult.topic.environment",  comment: ""), icon: "leaf.fill",         color: .green),
		TopicItem(id: "housing",      label: NSLocalizedString("consult.topic.housing",      comment: ""), icon: "house.fill",         color: .blue),
		TopicItem(id: "health",       label: NSLocalizedString("consult.topic.health",       comment: ""), icon: "heart.fill",         color: .red),
		TopicItem(id: "indigenous",   label: NSLocalizedString("consult.topic.indigenous",   comment: ""), icon: "person.3.fill",      color: .orange),
		TopicItem(id: "finance",      label: NSLocalizedString("consult.topic.finance",      comment: ""), icon: "chart.bar.fill",     color: .indigo),
		TopicItem(id: "immigration",  label: NSLocalizedString("consult.topic.immigration",  comment: ""), icon: "globe",              color: .teal),
		TopicItem(id: "agriculture",  label: NSLocalizedString("consult.topic.agriculture",  comment: ""), icon: "fork.knife",         color: .brown),
		TopicItem(id: "justice",      label: NSLocalizedString("consult.topic.justice",      comment: ""), icon: "scale.3d",           color: .purple),
	]

	var body: some View {
		List {
			Section {
				headerCard
			}

			// Topic rows all open the Consultations Finder — canada.ca does
			// not support deep-linking by topic (client-side JS filtering).
			// Users can filter interactively once on the official site.
			Section(NSLocalizedString("consult.section.browse", comment: "")) {
				ForEach(topics) { item in
					Button {
						openURL(Self.finderURL)
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

			Section(NSLocalizedString("consult.section.all", comment: "")) {
				linkRow(
					title: NSLocalizedString("consult.finder.title", comment: ""),
					subtitle: NSLocalizedString("consult.finder.subtitle", comment: ""),
					icon: "magnifyingglass.circle.fill",
					color: .blue,
					url: Self.finderURL
				)
				linkRow(
					title: NSLocalizedString("consult.portal.title", comment: ""),
					subtitle: NSLocalizedString("consult.portal.subtitle", comment: ""),
					icon: "list.bullet.rectangle.fill",
					color: .secondary,
					url: Self.portalURL
				)
			}

			Section {
				Text(NSLocalizedString("consult.explanation", comment: ""))
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.vertical, 4)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle(NSLocalizedString("consult.navTitle", comment: ""))
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
				Text(NSLocalizedString("consult.header.title", comment: ""))
					.font(.headline)
				Text(NSLocalizedString("consult.header.subtitle", comment: ""))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private func linkRow(title: String, subtitle: String, icon: String, color: Color, url: URL) -> some View {
		Button {
			openURL(url)
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
}
