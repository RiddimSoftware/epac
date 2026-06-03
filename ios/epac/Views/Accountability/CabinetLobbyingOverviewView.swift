import SwiftUI

private enum CabinetLobbyingOverviewLayout {
	static let sectionSpacing = EpacSpacing.m
	static let rowSpacing = EpacSpacing.xs
	static let rowPadding = EpacSpacing.s
	static let rankWidth: CGFloat = 34
	static let countWidth: CGFloat = 64
	static let cornerRadius = EpacCornerRadius.m
	static let loadingMinHeight: CGFloat = 160
	static let unavailableMinHeight: CGFloat = 220
	static let topOrganizationsLimit = 3
	static let rankOffset = 1
	static let allPortfolios = "All portfolios"
}

struct CabinetLobbyingOverviewView: View {
	private let load: LoadCabinetLobbyingOverview
	private let autoload: Bool

	@State private var overview: CabinetLobbyingOverview
	@State private var selectedPortfolio = CabinetLobbyingOverviewLayout.allPortfolios
	@State private var isLoading = false
	@State private var loadFailed = false
	@State private var loaded: Bool

	init(
		load: LoadCabinetLobbyingOverview = LoadCabinetLobbyingOverview(
			repository: BackendCabinetLobbyingRepository()
		),
		initialOverview: CabinetLobbyingOverview = .empty,
		initialLoadCompleted: Bool = false,
		autoload: Bool = true
	) {
		self.load = load
		self.autoload = autoload
		self._overview = State(initialValue: initialOverview)
		self._loaded = State(initialValue: initialLoadCompleted || !initialOverview.ministers.isEmpty)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: CabinetLobbyingOverviewLayout.sectionSpacing) {
				header

				if isLoading && overview.ministers.isEmpty {
					ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
						.frame(maxWidth: .infinity, minHeight: CabinetLobbyingOverviewLayout.loadingMinHeight)
				} else if loadFailed && overview.ministers.isEmpty {
					ContentUnavailableView(
						NSLocalizedString("lobbying.error.title", comment: ""),
						systemImage: "exclamationmark.triangle",
						description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
					)
					.frame(minHeight: CabinetLobbyingOverviewLayout.unavailableMinHeight)
				} else if loaded && overview.ministers.isEmpty {
					ContentUnavailableView(
						"No cabinet lobbying communications",
						systemImage: "building.columns",
						description: Text("No registered communications were returned for cabinet ministers.")
					)
					.frame(minHeight: CabinetLobbyingOverviewLayout.unavailableMinHeight)
				} else {
					filter
					ministersSection
					organizationsSection
				}
			}
			.padding()
			.adaptiveReadingWidth()
		}
		.navigationTitle("Cabinet Lobbying")
		.navigationBarTitleDisplayMode(.large)
		.task {
			guard autoload, !loaded, !isLoading else { return }
			await reload()
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: EpacSpacing.xs) {
			Label("Cabinet lobbying overview", systemImage: "person.2.wave.2.fill")
				.font(.headline)
			Text("Ministers ranked by registered lobbying communications.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var filter: some View {
		Picker("Portfolio", selection: $selectedPortfolio) {
			Text(CabinetLobbyingOverviewLayout.allPortfolios)
				.tag(CabinetLobbyingOverviewLayout.allPortfolios)
			ForEach(overview.portfolioFilters, id: \.self) { portfolio in
				Text(portfolio).tag(portfolio)
			}
		}
		.pickerStyle(.menu)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var ministersSection: some View {
		VStack(alignment: .leading, spacing: CabinetLobbyingOverviewLayout.rowSpacing) {
			Text("Minister ranking")
				.font(.subheadline.weight(.semibold))
			ForEach(Array(filteredMinisters.enumerated()), id: \.element.id) { index, minister in
				CabinetLobbyingMinisterRow(rank: index + CabinetLobbyingOverviewLayout.rankOffset, minister: minister)
			}
		}
		.padding()
		.background(Color.appSurface)
		.cornerRadius(CabinetLobbyingOverviewLayout.cornerRadius)
	}

	private var organizationsSection: some View {
		VStack(alignment: .leading, spacing: CabinetLobbyingOverviewLayout.rowSpacing) {
			Text("Most active organizations per portfolio")
				.font(.subheadline.weight(.semibold))
			ForEach(groupedOrganizations, id: \.portfolio) { group in
				CabinetLobbyingOrganizationGroup(portfolio: group.portfolio, organizations: group.organizations)
			}
		}
		.padding()
		.background(Color.appSurface)
		.cornerRadius(CabinetLobbyingOverviewLayout.cornerRadius)
	}

	private var filteredMinisters: [CabinetLobbyingMinisterSummary] {
		let ministers = selectedPortfolio == CabinetLobbyingOverviewLayout.allPortfolios
			? overview.ministers
			: overview.ministers.filter { $0.portfolioNames.contains(selectedPortfolio) }
		return ministers.sorted { lhs, rhs in
			if lhs.totalCommunications == rhs.totalCommunications {
				return lhs.ministerName < rhs.ministerName
			}
			return lhs.totalCommunications > rhs.totalCommunications
		}
	}

	private var groupedOrganizations: [(portfolio: String, organizations: [CabinetLobbyingOrganizationSummary])] {
		let organizations = selectedPortfolio == CabinetLobbyingOverviewLayout.allPortfolios
			? overview.mostActiveOrganizations
			: overview.mostActiveOrganizations.filter { $0.portfolioName == selectedPortfolio }
		let grouped = Dictionary(grouping: organizations, by: \.portfolioName)
		return grouped.keys.sorted().map { key in
			(
				portfolio: key,
				organizations: Array(grouped[key, default: []]
					.sorted { $0.communicationCount > $1.communicationCount }
					.prefix(CabinetLobbyingOverviewLayout.topOrganizationsLimit))
			)
		}
	}

	@MainActor
	private func reload() async {
		isLoading = true
		loadFailed = false
		defer {
			isLoading = false
			loaded = true
		}

		do {
			overview = try await load.execute()
		} catch {
			loadFailed = true
		}
	}
}

private struct CabinetLobbyingMinisterRow: View {
	let rank: Int
	let minister: CabinetLobbyingMinisterSummary

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: EpacSpacing.s) {
			Text("#\(rank)")
				.font(.caption.monospacedDigit().weight(.semibold))
				.foregroundStyle(.secondary)
				.frame(width: CabinetLobbyingOverviewLayout.rankWidth, alignment: .leading)
			VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
				Text(minister.ministerName)
					.font(.subheadline.weight(.semibold))
				Text(minister.portfolioName)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				if minister.mandateMatchCount > 0 {
					Text("\(minister.mandateMatchCount) mandate matches")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(Color.appWarning)
				}
			}
			Spacer(minLength: EpacSpacing.s)
			Text("\(minister.totalCommunications)")
				.font(.headline.monospacedDigit())
				.frame(width: CabinetLobbyingOverviewLayout.countWidth, alignment: .trailing)
				.accessibilityLabel("\(minister.totalCommunications) communications")
		}
		.padding(.vertical, CabinetLobbyingOverviewLayout.rowPadding)
		.accessibilityElement(children: .combine)
	}
}

private struct CabinetLobbyingOrganizationGroup: View {
	let portfolio: String
	let organizations: [CabinetLobbyingOrganizationSummary]

	var body: some View {
		VStack(alignment: .leading, spacing: EpacSpacing.xs) {
			Text(portfolio)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			ForEach(organizations) { organization in
				HStack(alignment: .firstTextBaseline) {
					Text(organization.organizationName)
						.font(.subheadline)
					Spacer(minLength: EpacSpacing.s)
					Text("\(organization.communicationCount)")
						.font(.subheadline.monospacedDigit().weight(.semibold))
						.accessibilityLabel("\(organization.communicationCount) communications")
				}
			}
		}
		.padding(.vertical, EpacSpacing.xs)
		.accessibilityElement(children: .combine)
	}
}
