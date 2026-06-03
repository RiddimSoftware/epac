import Observation
import SwiftUI

private enum LobbyistOrganizationDirectoryLayout {
	static let rowSpacing = EpacSpacing.xs
	static let compactSpacing = EpacSpacing.xxs
	static let countWidth: CGFloat = 44
	static let loadingMinHeight: CGFloat = 220
	static let perPage = 50
}

struct LobbyistOrganizationDirectoryView: View {
	@State private var viewModel: LobbyistOrganizationDirectoryViewModel

	init(
		repository: any LobbyistOrganizationRepository = BackendLobbyistOrganizationRepository(),
		initialDirectory: LobbyistOrganizationDirectory? = nil,
		autoload: Bool = true
	) {
		_viewModel = State(
			initialValue: LobbyistOrganizationDirectoryViewModel(
				repository: repository,
				initialDirectory: initialDirectory,
				autoload: autoload
			)
		)
	}

	var body: some View {
		Group {
			if viewModel.isLoading && viewModel.rows.isEmpty {
				ProgressView(NSLocalizedString("lobbying.loading", comment: ""))
					.frame(maxWidth: .infinity, minHeight: LobbyistOrganizationDirectoryLayout.loadingMinHeight)
			} else if viewModel.loadFailed && viewModel.rows.isEmpty {
				ContentUnavailableView(
					NSLocalizedString("lobbying.error.title", comment: ""),
					systemImage: "exclamationmark.triangle",
					description: Text(NSLocalizedString("lobbying.error.description", comment: ""))
				)
				.frame(maxWidth: .infinity, minHeight: LobbyistOrganizationDirectoryLayout.loadingMinHeight)
			} else if viewModel.rows.isEmpty {
				ContentUnavailableView(
					"No organizations found",
					systemImage: "building.2",
					description: Text("No OCL organizations match this search.")
				)
			} else {
				List {
					ForEach(viewModel.rows) { organization in
						NavigationLink(destination: LobbyistOrganizationView(organizationID: organization.id)) {
							LobbyistOrganizationDirectoryRowView(organization: organization)
						}
					}
					if let sourceURL = viewModel.sourceURL {
						Section {
							LobbyingSourceCitationView(url: sourceURL)
						}
					}
				}
				.listStyle(.plain)
				.accessibilityIdentifier("lobbyist-organization-directory")
			}
		}
		.navigationTitle("Lobbyist Organizations")
		.navigationBarTitleDisplayMode(.large)
		.searchable(text: $viewModel.searchText, prompt: "Search organizations")
		.onSubmit(of: .search) {
			Task { await viewModel.reload() }
		}
		.task {
			guard viewModel.autoload, viewModel.rows.isEmpty, !viewModel.isLoading else { return }
			await viewModel.reload()
		}
	}
}

private struct LobbyistOrganizationDirectoryRowView: View {
	let organization: LobbyistOrganizationDirectoryRow

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: LobbyistOrganizationDirectoryLayout.rowSpacing) {
			VStack(alignment: .leading, spacing: LobbyistOrganizationDirectoryLayout.compactSpacing) {
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
			Text("\(organization.communicationVolumeCurrentParliament)")
				.font(.subheadline.monospacedDigit().weight(.semibold))
				.frame(width: LobbyistOrganizationDirectoryLayout.countWidth, alignment: .trailing)
		}
		.padding(.vertical, EpacSpacing.xxs)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(
			"\(organization.name), \(organization.communicationVolumeCurrentParliament) current Parliament communications"
		)
	}
}

@MainActor
@Observable
private final class LobbyistOrganizationDirectoryViewModel {
	let autoload: Bool
	private let repository: any LobbyistOrganizationRepository

	var searchText = ""
	var directory: LobbyistOrganizationDirectory?
	var isLoading = false
	var loadFailed = false

	init(
		repository: any LobbyistOrganizationRepository,
		initialDirectory: LobbyistOrganizationDirectory?,
		autoload: Bool
	) {
		self.repository = repository
		self.directory = initialDirectory
		self.autoload = autoload
	}

	var rows: [LobbyistOrganizationDirectoryRow] {
		directory?.rows ?? []
	}

	var sourceURL: URL? {
		directory?.sourceURL
	}

	func reload() async {
		isLoading = true
		loadFailed = false
		defer { isLoading = false }

		do {
			directory = try await repository.browseLobbyistOrganizations(
				search: searchText,
				sector: nil,
				page: 1,
				perPage: LobbyistOrganizationDirectoryLayout.perPage
			)
		} catch {
			loadFailed = true
		}
	}
}
