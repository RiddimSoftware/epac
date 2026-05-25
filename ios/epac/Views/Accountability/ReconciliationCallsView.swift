//
//  ReconciliationCallsView.swift
//  epac
//
//  Created on 2026-04-28.
//

import SwiftUI

private enum ReconciliationLayout {
	static let headerSpacing: CGFloat = 12
	static let headerTextSpacing = EpacSpacing.xs
	static let compactVerticalPadding = EpacSpacing.xs
	static let filterSpacing: CGFloat = 10
	static let contextRowSpacing: CGFloat = 12
	static let contextIconWidth: CGFloat = 28
	static let contextTextSpacing: CGFloat = 3
	static let statusGridMinimum: CGFloat = 112
	static let statusGridSpacing = EpacSpacing.s
	static let statusItemSpacing: CGFloat = 6
	static let statusDotSize = EpacSpacing.s
	static let statusLineLimit = 1
	static let statusMinimumScaleFactor = 0.8
	static let statusHorizontalPadding: CGFloat = 10
	static let statusVerticalPadding: CGFloat = 7
	static let statusSummaryOpacity = EpacOpacity.tint
	static let callRowSpacing = EpacSpacing.s
	static let callRowHeaderSpacing: CGFloat = 10
	static let callRowTitleSpacing = EpacSpacing.xs
	static let statusSpacerLength = EpacSpacing.s
	static let statusSummaryLineLimit = 3
	static let detailHeaderSpacing: CGFloat = 10
	static let sourceRowSpacing: CGFloat = 12
	static let sourceIconWidth = EpacIconSize.m
	static let sourceTextSpacing = EpacSpacing.xs
	static let sourceVerticalPadding = EpacSpacing.xxs
	static let badgeHorizontalPadding = EpacSpacing.s
	static let badgeVerticalPadding: CGFloat = 5
	static let badgeOpacity: Double = 0.14
}

struct ReconciliationCallsView: View {
	@State private var dataset: ReconciliationCallsDataset?
	@State private var loadError: String?
	@State private var selectedTheme: ReconciliationTheme?
	@State private var selectedStatus: ReconciliationStatus?

	private var filteredCalls: [ReconciliationCall] {
		guard let calls = dataset?.calls else { return [] }
		return calls.filter { call in
			(selectedTheme == nil || call.theme == selectedTheme)
				&& (selectedStatus == nil || call.status == selectedStatus)
		}
	}

	var body: some View {
		Group {
			if let dataset {
				List {
					Section {
						header(dataset)
					}

					Section {
						filters
					}

					Section("Calls to Action") {
						ForEach(filteredCalls) { call in
							NavigationLink(destination: ReconciliationCallDetailView(call: call)) {
								ReconciliationCallRow(call: call)
							}
						}
					}

					Section("Curation") {
						Text(dataset.metadata.curationNote)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				.listStyle(.insetGrouped)
			} else if loadError != nil {
				EmptyStateView(
					icon: "exclamationmark.triangle",
					title: "Reconciliation tracker unavailable",
					message: "The local Calls to Action data could not be loaded.",
					action: nil
				)
			} else {
				ProgressView("Loading Calls to Action")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.navigationTitle("Calls to Action")
		.navigationBarTitleDisplayMode(.large)
		.task { load() }
	}

	private func load() {
		do {
			dataset = try ReconciliationCallsRepository.load()
			loadError = nil
		} catch {
			loadError = error.localizedDescription
		}
	}

	@ViewBuilder
	private func header(_ dataset: ReconciliationCallsDataset) -> some View {
		VStack(alignment: .leading, spacing: ReconciliationLayout.headerSpacing) {
			VStack(alignment: .leading, spacing: ReconciliationLayout.headerTextSpacing) {
				Text(dataset.metadata.title)
					.font(.headline)
				Text("Reviewed \(dataset.metadata.lastReviewed)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			ReconciliationStatusSummary(calls: dataset.calls)

			HStack {
				DataSourceBadge(source: .reconciliationCalls())
				Spacer()
				if let trcURL = URL(string: dataset.metadata.trcPublicationUrl) {
					Link(destination: trcURL) {
						Label("TRC text", systemImage: "doc.text")
					}
					.font(.caption)
				}
			}
		}
		.padding(.vertical, ReconciliationLayout.compactVerticalPadding)
	}

	private var filters: some View {
		VStack(spacing: ReconciliationLayout.filterSpacing) {
			Picker("Theme", selection: $selectedTheme) {
				Text("All themes").tag(nil as ReconciliationTheme?)
				ForEach(ReconciliationTheme.allCases) { theme in
					Text(theme.rawValue).tag(theme as ReconciliationTheme?)
				}
			}

			Picker("Status", selection: $selectedStatus) {
				Text("All statuses").tag(nil as ReconciliationStatus?)
				ForEach(ReconciliationStatus.allCases, id: \.rawValue) { status in
					Text(status.rawValue).tag(status as ReconciliationStatus?)
				}
			}
		}
		.pickerStyle(.menu)
	}
}

struct ReconciliationContextCard: View {
	var body: some View {
		NavigationLink(destination: ReconciliationCallsView()) {
			HStack(alignment: .top, spacing: ReconciliationLayout.contextRowSpacing) {
				Image(systemName: "figure.stand.line.dotted.figure.stand")
					.foregroundStyle(.orange)
					.frame(width: ReconciliationLayout.contextIconWidth)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: ReconciliationLayout.contextTextSpacing) {
					Text("TRC Calls to Action")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
					Text("Track implementation status across the 94 reconciliation commitments")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.accessibilityHint("Opens Truth and Reconciliation Commission Calls to Action tracker")
	}
}

private struct ReconciliationStatusSummary: View {
	let calls: [ReconciliationCall]

	private var counts: [(ReconciliationStatus, Int)] {
		ReconciliationStatus.allCases.compactMap { status in
			let count = calls.filter { $0.status == status }.count
			return count > 0 ? (status, count) : nil
		}
	}

	var body: some View {
		LazyVGrid(
			columns: [GridItem(.adaptive(minimum: ReconciliationLayout.statusGridMinimum), spacing: ReconciliationLayout.statusGridSpacing)],
			alignment: .leading,
			spacing: ReconciliationLayout.statusGridSpacing
		) {
			ForEach(counts, id: \.0.rawValue) { status, count in
				HStack(spacing: ReconciliationLayout.statusItemSpacing) {
					Circle()
						.fill(status.tone.color)
						.frame(width: ReconciliationLayout.statusDotSize, height: ReconciliationLayout.statusDotSize)
					Text("\(count) \(status.rawValue)")
						.font(.caption.weight(.semibold))
						.lineLimit(ReconciliationLayout.statusLineLimit)
						.minimumScaleFactor(ReconciliationLayout.statusMinimumScaleFactor)
				}
				.padding(.horizontal, ReconciliationLayout.statusHorizontalPadding)
				.padding(.vertical, ReconciliationLayout.statusVerticalPadding)
				.background(status.tone.color.opacity(ReconciliationLayout.statusSummaryOpacity), in: Capsule())
				.foregroundStyle(.primary)
			}
		}
	}
}

private struct ReconciliationCallRow: View {
	let call: ReconciliationCall

	var body: some View {
		VStack(alignment: .leading, spacing: ReconciliationLayout.callRowSpacing) {
			HStack(alignment: .top, spacing: ReconciliationLayout.callRowHeaderSpacing) {
				VStack(alignment: .leading, spacing: ReconciliationLayout.callRowTitleSpacing) {
					Text("Call \(call.number)")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Text(call.title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: ReconciliationLayout.statusSpacerLength)
				ReconciliationStatusBadge(status: call.status)
			}

			Text(call.theme.rawValue)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(call.statusSummary)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(ReconciliationLayout.statusSummaryLineLimit)
		}
		.padding(.vertical, ReconciliationLayout.compactVerticalPadding)
	}
}

private struct ReconciliationCallDetailView: View {
	let call: ReconciliationCall

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: ReconciliationLayout.detailHeaderSpacing) {
					ReconciliationStatusBadge(status: call.status)
					Text("Call \(call.number): \(call.title)")
						.font(.headline)
					Text(call.statusSummary)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, ReconciliationLayout.compactVerticalPadding)
			}

			Section("Call Text") {
				Text(call.callText)
					.font(.body)
			}

			Section("Status Attribution") {
				LabeledContent("Theme", value: call.theme.rawValue)
				LabeledContent("Responsible party", value: call.responsibleParty)
				LabeledContent("Implementation phase", value: call.implementationPhase)
				Text(call.statusAttribution)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}

			Section("Status History") {
				ForEach(call.statusHistory) { item in
					sourceLink(
						title: "\(item.year): \(item.status)",
						subtitle: item.source,
						urlString: item.url,
						icon: "clock.arrow.circlepath"
					)
				}
			}

			Section("Sources") {
				sourceLink(
					title: call.trcSource.title,
					subtitle: "Original TRC Calls to Action text",
					urlString: call.trcSource.url,
					icon: "doc.text.fill"
				)
				sourceLink(
					title: call.statusSource.title,
					subtitle: "Status detail, updated \(call.statusSource.lastUpdated)",
					urlString: call.statusSource.url,
					icon: "checkmark.seal.fill"
				)
				sourceLink(
					title: call.primarySource.title,
					subtitle: "Primary citation for this status note",
					urlString: call.primarySource.url,
					icon: "link"
				)
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Call \(call.number)")
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
		HStack(alignment: .top, spacing: ReconciliationLayout.sourceRowSpacing) {
			Image(systemName: icon)
				.foregroundStyle(.orange)
				.frame(width: ReconciliationLayout.sourceIconWidth)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: ReconciliationLayout.sourceTextSpacing) {
				Text(title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: ReconciliationLayout.statusSpacerLength)
			Image(systemName: "arrow.up.right.square")
				.font(.caption)
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, ReconciliationLayout.sourceVerticalPadding)
	}
}

private struct ReconciliationStatusBadge: View {
	let status: ReconciliationStatus

	var body: some View {
		Text(status.rawValue)
			.font(.caption2.weight(.bold))
			.foregroundStyle(status.tone.color)
			.padding(.horizontal, ReconciliationLayout.badgeHorizontalPadding)
			.padding(.vertical, ReconciliationLayout.badgeVerticalPadding)
			.background(status.tone.color.opacity(ReconciliationLayout.badgeOpacity), in: Capsule())
			.accessibilityLabel("Status: \(status.rawValue)")
	}
}

private extension ReconciliationStatusTone {
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
