//
//  PromiseTrackerView.swift
//  epac
//
//  Created on 2026-04-28.
//

import SwiftUI

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
		VStack(alignment: .leading, spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
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
		.padding(.vertical, 4)
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
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
			ForEach(counts, id: \.0.rawValue) { status, count in
				HStack(spacing: 6) {
					Circle()
						.fill(status.tone.color)
						.frame(width: 8, height: 8)
					Text("\(count) \(status.rawValue)")
						.font(.caption.weight(.semibold))
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 7)
				.background(status.tone.color.opacity(0.12), in: Capsule())
				.foregroundStyle(.primary)
			}
		}
	}
}

private struct PromiseCommitmentRow: View {
	let commitment: PromiseCommitment

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .top, spacing: 10) {
				VStack(alignment: .leading, spacing: 4) {
					Text(commitment.promise)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.fixedSize(horizontal: false, vertical: true)
					Text(commitment.category)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				PromiseStatusBadge(status: commitment.status)
			}

			Text(commitment.statusRationale)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(3)
		}
		.padding(.vertical, 4)
	}
}

private struct PromiseStatusBadge: View {
	let status: PromiseTrackerStatus

	var body: some View {
		Text(status.rawValue)
			.font(.caption2.weight(.bold))
			.foregroundStyle(status.tone.color)
			.padding(.horizontal, 8)
			.padding(.vertical, 5)
			.background(status.tone.color.opacity(0.14), in: Capsule())
			.accessibilityLabel("Status: \(status.rawValue)")
	}
}

private struct PromiseCommitmentDetailView: View {
	let commitment: PromiseCommitment

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: 10) {
					PromiseStatusBadge(status: commitment.status)
					Text(commitment.promise)
						.font(.headline)
					Text(commitment.statusRationale)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 4)
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
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: icon)
				.foregroundStyle(.blue)
				.frame(width: 24)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 8)
			Image(systemName: "arrow.up.right.square")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, 2)
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
