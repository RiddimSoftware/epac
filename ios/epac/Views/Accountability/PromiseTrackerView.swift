//
//  PromiseTrackerView.swift
//  epac
//
//  Created on 2026-04-28.
//

import SwiftUI

private enum PromiseTrackerLayout {
	static let headerSpacing: CGFloat = 12
	static let headerTextSpacing = EpacSpacing.xs
	static let compactVerticalPadding = EpacSpacing.xs
	static let statusGridMinimum: CGFloat = 112
	static let statusGridSpacing = EpacSpacing.s
	static let statusItemSpacing: CGFloat = 6
	static let statusDotSize = EpacSpacing.s
	static let statusLineLimit = 1
	static let statusMinimumScaleFactor = 0.8
	static let statusHorizontalPadding: CGFloat = 10
	static let statusVerticalPadding: CGFloat = 7
	static let statusSummaryOpacity = EpacOpacity.tint
	static let commitmentRowSpacing = EpacSpacing.s
	static let commitmentHeaderSpacing: CGFloat = 10
	static let commitmentTextSpacing = EpacSpacing.xs
	static let statusSpacerLength = EpacSpacing.s
	static let statusRationaleLineLimit = 3
	static let badgeHorizontalPadding = EpacSpacing.s
	static let badgeVerticalPadding: CGFloat = 5
	static let badgeOpacity: Double = 0.14
	static let detailHeaderSpacing: CGFloat = 10
	static let sourceRowSpacing: CGFloat = 12
	static let sourceIconWidth = EpacIconSize.m
	static let sourceTextSpacing = EpacSpacing.xs
	static let sourceVerticalPadding = EpacSpacing.xxs
}

struct PromiseTrackerView: View {
	@State private var dataset: PromiseTrackerDataset?
	@State private var loadError: String?

	var body: some View {
		Group {
			if let dataset {
				List {
					Section {
						header(dataset)
					}

					Section("Commitments") {
						ForEach(dataset.commitments) { commitment in
							NavigationLink(destination: PromiseCommitmentDetailView(commitment: commitment)) {
								PromiseCommitmentRow(commitment: commitment)
							}
						}
					}

					Section("Review Policy") {
						Text(dataset.metadata.reviewPolicy)
							.font(.footnote)
							.foregroundStyle(.secondary)
						Text(dataset.metadata.curationNote)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				.listStyle(.insetGrouped)
			} else if loadError != nil {
				EmptyStateView(
					icon: "exclamationmark.triangle",
					title: "Promise tracker unavailable",
					message: "The local promise tracker data could not be loaded.",
					action: nil
				)
			} else {
				ProgressView("Loading promises")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.navigationTitle("Promise Tracker")
		.navigationBarTitleDisplayMode(.large)
		.task { load() }
	}

	private func load() {
		do {
			dataset = try PromiseTrackerRepository.load()
			loadError = nil
		} catch {
			loadError = error.localizedDescription
		}
	}

	@ViewBuilder
	private func header(_ dataset: PromiseTrackerDataset) -> some View {
		VStack(alignment: .leading, spacing: PromiseTrackerLayout.headerSpacing) {
			VStack(alignment: .leading, spacing: PromiseTrackerLayout.headerTextSpacing) {
				Text(dataset.metadata.governingParty)
					.font(.headline)
				Text(dataset.metadata.platformTitle)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Text("Reviewed \(dataset.metadata.lastReviewed)")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}

			PromiseStatusSummary(commitments: dataset.commitments)

			if let platformURL = URL(string: dataset.metadata.platformUrl),
			   let governmentURL = URL(string: dataset.metadata.governmentVerificationUrl) {
				HStack {
					Link(destination: platformURL) {
						Label("Platform", systemImage: "doc.text")
					}
					Spacer()
					Link(destination: governmentURL) {
						Label("Government", systemImage: "building.columns")
					}
				}
				.font(.caption)
			}
		}
		.padding(.vertical, PromiseTrackerLayout.compactVerticalPadding)
	}
}

private struct PromiseStatusSummary: View {
	let commitments: [PromiseCommitment]

	private var counts: [(PromiseTrackerStatus, Int)] {
		PromiseTrackerStatus.allCases.compactMap { status in
			let count = commitments.filter { $0.status == status }.count
			return count > 0 ? (status, count) : nil
		}
	}

	var body: some View {
		LazyVGrid(
			columns: [GridItem(.adaptive(minimum: PromiseTrackerLayout.statusGridMinimum), spacing: PromiseTrackerLayout.statusGridSpacing)],
			alignment: .leading,
			spacing: PromiseTrackerLayout.statusGridSpacing
		) {
			ForEach(counts, id: \.0.rawValue) { status, count in
				HStack(spacing: PromiseTrackerLayout.statusItemSpacing) {
					Circle()
						.fill(status.tone.color)
						.frame(width: PromiseTrackerLayout.statusDotSize, height: PromiseTrackerLayout.statusDotSize)
					Text("\(count) \(status.rawValue)")
						.font(.caption.weight(.semibold))
						.lineLimit(PromiseTrackerLayout.statusLineLimit)
						.minimumScaleFactor(PromiseTrackerLayout.statusMinimumScaleFactor)
				}
				.padding(.horizontal, PromiseTrackerLayout.statusHorizontalPadding)
				.padding(.vertical, PromiseTrackerLayout.statusVerticalPadding)
				.background(status.tone.color.opacity(PromiseTrackerLayout.statusSummaryOpacity), in: Capsule())
				.foregroundStyle(.primary)
			}
		}
	}
}

private struct PromiseCommitmentRow: View {
	let commitment: PromiseCommitment

	var body: some View {
		VStack(alignment: .leading, spacing: PromiseTrackerLayout.commitmentRowSpacing) {
			HStack(alignment: .top, spacing: PromiseTrackerLayout.commitmentHeaderSpacing) {
				VStack(alignment: .leading, spacing: PromiseTrackerLayout.commitmentTextSpacing) {
					Text(commitment.promise)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.fixedSize(horizontal: false, vertical: true)
					Text(commitment.category)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: PromiseTrackerLayout.statusSpacerLength)
				PromiseStatusBadge(status: commitment.status)
			}

			Text(commitment.statusRationale)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(PromiseTrackerLayout.statusRationaleLineLimit)
		}
		.padding(.vertical, PromiseTrackerLayout.compactVerticalPadding)
	}
}

private struct PromiseStatusBadge: View {
	let status: PromiseTrackerStatus

	var body: some View {
		Text(status.rawValue)
			.font(.caption2.weight(.bold))
			.foregroundStyle(status.tone.color)
			.padding(.horizontal, PromiseTrackerLayout.badgeHorizontalPadding)
			.padding(.vertical, PromiseTrackerLayout.badgeVerticalPadding)
			.background(status.tone.color.opacity(PromiseTrackerLayout.badgeOpacity), in: Capsule())
			.accessibilityLabel("Status: \(status.rawValue)")
	}
}

private struct PromiseCommitmentDetailView: View {
	let commitment: PromiseCommitment

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: PromiseTrackerLayout.detailHeaderSpacing) {
					PromiseStatusBadge(status: commitment.status)
					Text(commitment.promise)
						.font(.headline)
					Text(commitment.statusRationale)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, PromiseTrackerLayout.compactVerticalPadding)
			}

			Section("Platform Source") {
				sourceLink(
					title: commitment.source.title,
					subtitle: commitment.source.location,
					urlString: commitment.source.url,
					icon: "doc.text.fill"
				)
			}

			Section("Evidence") {
				ForEach(commitment.evidence) { item in
					sourceLink(
						title: item.title,
						subtitle: "\(item.type): \(item.citation)",
						urlString: item.url,
						icon: "checkmark.seal.fill"
					)
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle(commitment.status.rawValue)
		.navigationBarTitleDisplayMode(.inline)
	}

	private func sourceLink(title: String, subtitle: String, urlString: String, icon: String) -> some View {
		Group {
			if let url = URL(string: urlString) {
				Link(destination: url) {
					sourceLabel(title: title, subtitle: subtitle, icon: icon)
				}
			} else {
				sourceLabel(title: title, subtitle: subtitle, icon: icon)
			}
		}
	}

	private func sourceLabel(title: String, subtitle: String, icon: String) -> some View {
		HStack(alignment: .top, spacing: PromiseTrackerLayout.sourceRowSpacing) {
			Image(systemName: icon)
				.foregroundStyle(.blue)
				.frame(width: PromiseTrackerLayout.sourceIconWidth)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: PromiseTrackerLayout.sourceTextSpacing) {
				Text(title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: PromiseTrackerLayout.statusSpacerLength)
			Image(systemName: "arrow.up.right.square")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, PromiseTrackerLayout.sourceVerticalPadding)
	}
}

private extension PromiseTrackerStatusTone {
	var color: Color {
		switch self {
		case .green:
			return .green
		case .amber:
			return .orange
		case .red:
			return .red
		}
	}
}
