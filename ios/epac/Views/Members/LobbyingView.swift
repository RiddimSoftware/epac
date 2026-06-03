//
//  LobbyingView.swift
//  epac
//
//  MP lobbying exposure tab sourced from the backend OCL read model.
//

import Charts
import Observation
import SwiftUI

private enum MPLobbyingLayout {
	static let cardCornerRadius = EpacCornerRadius.m
	static let smallCornerRadius = EpacCornerRadius.s
	static let cardSpacing = EpacSpacing.m
	static let rowSpacing = EpacSpacing.xs
	static let rowPadding = EpacSpacing.s
	static let compactSpacing = EpacSpacing.xxs
	static let sectionSpacing = EpacSpacing.s
	static let statSpacing = EpacSpacing.xs
	static let statColumnSpacing = EpacSpacing.s
	static let chartHeight: CGFloat = 180
	static let loadingMinHeight: CGFloat = 120
	static let unavailableMinHeight: CGFloat = 220
	static let topSummaryOrganizationsLimit = 3
	static let topOrganizationsLimit = 5
	static let highConfidenceThreshold = 0.8
	static let comparisonSignificantThreshold = 0.05
	static let organizationCountColumnWidth: CGFloat = 44
	static let pillHorizontalPadding: CGFloat = 8
	static let pillVerticalPadding: CGFloat = 4
	static let pillOpacity = 0.14
	static let relatedBillSpacing = EpacSpacing.xxs
}

struct LobbyingView: View {
	@State private var viewModel: MPLobbyingViewModel

	init(
		memberID: Int,
		parliament: Int = MPLobbyingExposureDefaults.currentParliament,
		load: LoadMPLobbyingExposure = LoadMPLobbyingExposure(repository: BackendMPLobbyingExposureRepository()),
		initialExposure: MPLobbyingExposure? = nil,
		initialSubjectSlug: String = MPLobbyingViewModel.allSubjectsSlug,
		initialLoadCompleted: Bool = false,
		autoload: Bool = true
	) {
		_viewModel = State(
			initialValue: MPLobbyingViewModel(
				memberID: memberID,
				parliament: parliament,
				load: load,
				initialExposure: initialExposure,
				initialSubjectSlug: initialSubjectSlug,
				initialLoadCompleted: initialLoadCompleted,
				autoload: autoload
			)
		)
	}

	init(member: ParliamentMember) {
		self.init(memberID: member.memberID)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.cardSpacing) {
			header

			if viewModel.isLoading && viewModel.exposure == nil {
				ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
					.frame(maxWidth: .infinity, minHeight: MPLobbyingLayout.loadingMinHeight)
			} else if viewModel.loadFailed && viewModel.exposure == nil {
				ContentUnavailableView(
					NSLocalizedString("lobbying.error.title", comment: ""),
					systemImage: "exclamationmark.triangle",
					description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
				)
				.frame(minHeight: MPLobbyingLayout.unavailableMinHeight)
			} else if let exposure = viewModel.exposure {
				if exposure.summary.totalCommunicationCount == .zero {
					emptyState(sourceURL: exposure.sourceURL)
				} else {
					summaryCard(exposure.summary)
					topOrganizations(exposure.summary.topOrganizations, sourceURL: exposure.sourceURL)
					subjectChart(exposure.subjectBreakdown)
					filters
					timeline(exposure: exposure)
				}
			}
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.appSurface)
		.cornerRadius(MPLobbyingLayout.cardCornerRadius)
		.accessibilityIdentifier("mp-lobbying-tab")
		.task(id: viewModel.memberID) {
			guard viewModel.autoload, !viewModel.loaded, !viewModel.isLoading else { return }
			await viewModel.reload()
		}
	}

	private var header: some View {
		HStack(alignment: .firstTextBaseline) {
			Label("Lobbying", systemImage: "person.fill.badge.plus")
				.font(.headline)
			Spacer()
			if let exposure = viewModel.exposure {
				Text("\(exposure.summary.totalCommunicationCount)")
					.font(.headline.monospacedDigit())
					.foregroundStyle(.secondary)
					.accessibilityLabel("\(exposure.summary.totalCommunicationCount) communications")
			}
		}
	}

	private func summaryCard(_ summary: MPLobbyingSummary) -> some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
			HStack(spacing: MPLobbyingLayout.statColumnSpacing) {
				statCell(
					value: "\(summary.totalCommunicationCount)",
					label: "Communications",
					systemImage: "bubble.left.and.bubble.right.fill"
				)
				statCell(
					value: "\(summary.uniqueOrganizationsCount)",
					label: "Organizations",
					systemImage: "building.2.fill"
				)
			}

			topThreeSummary(summary.topOrganizations)
			Text(trendText(summary.trendVsPreviousParliament))
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Text(comparisonText(summary))
				.font(.caption.weight(.semibold))
				.foregroundStyle(.primary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(MPLobbyingLayout.rowPadding)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(MPLobbyingLayout.smallCornerRadius)
		.accessibilityElement(children: .combine)
	}

	private func statCell(value: String, label: String, systemImage: String) -> some View {
		VStack(spacing: MPLobbyingLayout.statSpacing) {
			Image(systemName: systemImage)
				.font(.caption)
				.foregroundStyle(Color.accentColor)
				.accessibilityHidden(true)
			Text(value)
				.font(.title3.bold().monospacedDigit())
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(value) \(label)")
	}

	@ViewBuilder
	private func topThreeSummary(_ organizations: [MPLobbyingTopOrganization]) -> some View {
		if !organizations.isEmpty {
			Text(
				"Top organizations: " +
				organizations
					.prefix(MPLobbyingLayout.topSummaryOrganizationsLimit)
					.map(\.name)
					.joined(separator: ", ")
			)
			.font(.caption)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func topOrganizations(_ organizations: [MPLobbyingTopOrganization], sourceURL: URL) -> some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
			Text("Top Lobbying Organizations")
				.font(.subheadline.weight(.semibold))

			ForEach(Array(organizations.prefix(MPLobbyingLayout.topOrganizationsLimit))) { organization in
				NavigationLink(destination: LobbyistOrganizationProfilePreview(organization: organization, sourceURL: sourceURL)) {
					HStack(alignment: .firstTextBaseline, spacing: MPLobbyingLayout.rowSpacing) {
						VStack(alignment: .leading, spacing: MPLobbyingLayout.compactSpacing) {
							Text(organization.name)
								.font(.subheadline.weight(.semibold))
								.fixedSize(horizontal: false, vertical: true)
							if let sector = organization.sector, !sector.isEmpty {
								Text(sector)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						Spacer(minLength: EpacSpacing.s)
						Text("\(organization.communicationCount)")
							.font(.subheadline.monospacedDigit().weight(.semibold))
							.frame(width: MPLobbyingLayout.organizationCountColumnWidth, alignment: .trailing)
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
				.buttonStyle(.plain)
				.padding(MPLobbyingLayout.rowPadding)
				.background(Color(.secondarySystemBackground))
				.cornerRadius(MPLobbyingLayout.smallCornerRadius)
			}
		}
	}

	@ViewBuilder
	private func subjectChart(_ subjects: [MPLobbyingSubjectDistribution]) -> some View {
		if !subjects.isEmpty {
			VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
				Text("Subject Breakdown")
					.font(.subheadline.weight(.semibold))
				Chart(subjects) { subject in
					BarMark(
						x: .value("Communications", subject.communicationCount),
						y: .value("Subject", subject.subjectMatter)
					)
					.foregroundStyle(Color.accentColor)
				}
				.chartXAxis {
					AxisMarks(position: .bottom)
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.frame(height: MPLobbyingLayout.chartHeight)
				.accessibilityIdentifier("mp-lobbying-subject-chart")
			}
		}
	}

	private var filters: some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
			Picker("Date range", selection: windowBinding) {
				ForEach(MPLobbyingWindow.allCases) { window in
					Text(window.displayName).tag(window)
				}
			}
			.pickerStyle(.segmented)

			Picker("Subject matter", selection: subjectBinding) {
				Text("All subjects").tag(MPLobbyingViewModel.allSubjectsSlug)
				ForEach(viewModel.subjectFilters) { subject in
					Text(subject.title).tag(subject.slug)
				}
			}
			.pickerStyle(.menu)
			.accessibilityIdentifier("mp-lobbying-subject-filter")
		}
	}

	private var windowBinding: Binding<MPLobbyingWindow> {
		Binding {
			viewModel.selectedWindow
		} set: { newWindow in
			viewModel.selectedWindow = newWindow
			Task { await viewModel.reload() }
		}
	}

	private var subjectBinding: Binding<String> {
		Binding {
			viewModel.selectedSubjectSlug
		} set: { newSubject in
			viewModel.selectedSubjectSlug = newSubject
		}
	}

	private func timeline(exposure: MPLobbyingExposure) -> some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
			Text("Communications Timeline")
				.font(.subheadline.weight(.semibold))

			if viewModel.filteredTimeline.isEmpty {
				Text("No communications match this subject filter.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(MPLobbyingLayout.rowPadding)
					.background(Color(.secondarySystemBackground))
					.cornerRadius(MPLobbyingLayout.smallCornerRadius)
			} else {
				ForEach(viewModel.filteredTimeline) { entry in
					MPLobbyingTimelineRow(entry: entry)
				}
			}

			if viewModel.canLoadMore {
				Button {
					Task { await viewModel.loadNextPage() }
				} label: {
					if viewModel.isLoadingNextPage {
						ProgressView()
					} else {
						Label("Load 50 more", systemImage: "arrow.down.circle")
					}
				}
				.buttonStyle(.bordered)
				.disabled(viewModel.isLoadingNextPage)
				.accessibilityIdentifier("mp-lobbying-load-more")
			}

			LobbyingSourceCitationView(url: exposure.sourceURL)
		}
		.accessibilityIdentifier("mp-lobbying-timeline")
	}

	private func emptyState(sourceURL: URL) -> some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
			ContentUnavailableView(
				NSLocalizedString("lobbying.empty.title", comment: ""),
				systemImage: "person.fill.badge.plus",
				description: Text(NSLocalizedString("lobbying.empty.description", comment: ""))
			)
			.frame(minHeight: MPLobbyingLayout.unavailableMinHeight)
			LobbyingSourceCitationView(url: sourceURL)
		}
	}

	private func trendText(_ trend: MPLobbyingTrend) -> String {
		if trend.delta > .zero {
			return "+\(trend.delta) vs previous Parliament"
		}
		if trend.delta < .zero {
			return "\(trend.delta) vs previous Parliament"
		}
		return "No change vs previous Parliament"
	}

	private func comparisonText(_ summary: MPLobbyingSummary) -> String {
		let party = comparisonPhrase(total: summary.totalCommunicationCount, average: summary.partyAverageCommunications)
		let national = comparisonPhrase(total: summary.totalCommunicationCount, average: summary.nationalAverageCommunications)
		return "\(party) party average · \(national) more than average MP"
	}

	private func comparisonPhrase(total: Int, average: Double) -> String {
		guard average > .zero else { return "No" }
		let ratio = Double(total) / average
		if abs(ratio - 1) < MPLobbyingLayout.comparisonSignificantThreshold {
			return "About 1x"
		}
		let label = ratio.formatted(.number.precision(.fractionLength(1)))
		return "\(label)x"
	}
}

private struct MPLobbyingTimelineRow: View {
	let entry: MPLobbyingTimelineEntry

	var body: some View {
		VStack(alignment: .leading, spacing: MPLobbyingLayout.rowSpacing) {
			HStack(alignment: .firstTextBaseline, spacing: MPLobbyingLayout.rowSpacing) {
				Text(entry.organizationName)
					.font(.subheadline.weight(.semibold))
					.fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: EpacSpacing.s)
				if let date = entry.date {
					Text(Self.dateFormatter.string(from: date))
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}

			if let sector = entry.organizationSector, !sector.isEmpty {
				Text(sector)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Text(entry.subjectMatter)
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			HStack(spacing: MPLobbyingLayout.relatedBillSpacing) {
				Text(entry.communicationType.displayLabel)
					.font(.caption2.weight(.semibold))
					.padding(.horizontal, MPLobbyingLayout.pillHorizontalPadding)
					.padding(.vertical, MPLobbyingLayout.pillVerticalPadding)
					.background(Color.accentColor.opacity(MPLobbyingLayout.pillOpacity))
					.clipShape(Capsule())

				if let bill = entry.billCrossReference,
				   bill.mappingConfidence >= MPLobbyingLayout.highConfidenceThreshold {
					Link(destination: bill.url) {
						Label("See related bill", systemImage: "doc.text.magnifyingglass")
							.font(.caption2)
					}
				}
			}

			LobbyingSourceCitationView(url: entry.sourceURL)
		}
		.padding(MPLobbyingLayout.rowPadding)
		.background(Color(.secondarySystemBackground))
		.cornerRadius(MPLobbyingLayout.smallCornerRadius)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
	}

	private var accessibilityLabel: String {
		var parts = [entry.organizationName, entry.subjectMatter, entry.communicationType.displayLabel]
		if let sector = entry.organizationSector, !sector.isEmpty {
			parts.append(sector)
		}
		if let date = entry.date {
			parts.append(Self.dateFormatter.string(from: date))
		}
		return parts.joined(separator: ", ")
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()
}

private struct LobbyistOrganizationProfilePreview: View {
	let organization: MPLobbyingTopOrganization
	let sourceURL: URL

	var body: some View {
		List {
			Section {
				VStack(alignment: .leading, spacing: MPLobbyingLayout.sectionSpacing) {
					Text(organization.name)
						.font(.title3.weight(.semibold))
						.fixedSize(horizontal: false, vertical: true)
					if let sector = organization.sector, !sector.isEmpty {
						Text(sector)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, EpacSpacing.xs)
			}

			Section("Current Parliament") {
				LabeledContent("Communications", value: "\(organization.communicationCount)")
			}

			Section("Source") {
				LobbyingSourceCitationView(url: sourceURL)
			}
		}
		.navigationTitle("Organization Profile")
		.navigationBarTitleDisplayMode(.inline)
	}
}

struct MPLobbyingSubjectFilter: Identifiable, Equatable {
	let slug: String
	let title: String

	var id: String {
		slug
	}
}

@MainActor
@Observable
final class MPLobbyingViewModel {
	static let allSubjectsSlug = "all"

	let memberID: Int
	let parliament: Int
	let autoload: Bool
	private let load: LoadMPLobbyingExposure

	var exposure: MPLobbyingExposure?
	var selectedWindow: MPLobbyingWindow
	var selectedSubjectSlug = allSubjectsSlug
	var isLoading = false
	var isLoadingNextPage = false
	var loadFailed = false
	var loaded: Bool

	init(
		memberID: Int,
		parliament: Int,
		load: LoadMPLobbyingExposure,
		initialExposure: MPLobbyingExposure?,
		initialSubjectSlug: String,
		initialLoadCompleted: Bool,
		autoload: Bool
	) {
		self.memberID = memberID
		self.parliament = parliament
		self.load = load
		self.exposure = initialExposure
		self.selectedWindow = initialExposure?.window ?? .threeMonths
		self.selectedSubjectSlug = initialSubjectSlug
		self.loaded = initialLoadCompleted || initialExposure != nil
		self.autoload = autoload
	}

	var canLoadMore: Bool {
		guard let exposure else { return false }
		return exposure.page < exposure.pages
	}

	var subjectFilters: [MPLobbyingSubjectFilter] {
		guard let exposure else { return [] }
		return exposure.subjectBreakdown.map {
			MPLobbyingSubjectFilter(slug: $0.subjectSlug, title: $0.subjectMatter)
		}
	}

	var filteredTimeline: [MPLobbyingTimelineEntry] {
		guard selectedSubjectSlug != Self.allSubjectsSlug else {
			return exposure?.timeline ?? []
		}
		return exposure?.timeline.filter { $0.subjectSlug == selectedSubjectSlug } ?? []
	}

	func reload() async {
		isLoading = true
		loadFailed = false
		defer {
			isLoading = false
			loaded = true
		}

		do {
			exposure = try await load.execute(
				memberID: memberID,
				parliament: parliament,
				window: selectedWindow
			)
			selectedSubjectSlug = Self.allSubjectsSlug
		} catch {
			loadFailed = true
		}
	}

	func loadNextPage() async {
		guard let exposure, canLoadMore, !isLoadingNextPage else { return }
		isLoadingNextPage = true
		loadFailed = false
		defer { isLoadingNextPage = false }

		do {
			let nextPage = try await load.execute(
				memberID: memberID,
				parliament: parliament,
				window: selectedWindow,
				page: exposure.page + 1
			)
			self.exposure = exposure.appendingTimeline(from: nextPage)
		} catch {
			loadFailed = true
		}
	}
}

private extension MPLobbyingWindow {
	var displayName: String {
		switch self {
		case .last30Days:
			"30 days"
		case .threeMonths:
			"3 months"
		case .twelveMonths:
			"12 months"
		case .allTime:
			"All"
		}
	}
}

private extension String {
	var displayLabel: String {
		switch lowercased() {
		case "meeting":
			"Meeting"
		case "written":
			"Written"
		default:
			isEmpty ? "Communication" : self
		}
	}
}
