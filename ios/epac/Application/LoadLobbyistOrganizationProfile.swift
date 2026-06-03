import Foundation

enum LobbyistOrganizationProfileLoadError: Error {
	case organizationNotFound(String)
}

struct LoadLobbyistOrganizationProfile: Sendable {
	private static let directoryMatchLimit = 10

	let repository: any LobbyistOrganizationRepository

	func execute(id: String) async throws -> LobbyistOrganization {
		try await repository.loadLobbyistOrganizationProfile(id: id)
	}

	func execute(organizationName: String) async throws -> LobbyistOrganization {
		let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw LobbyistOrganizationProfileLoadError.organizationNotFound(trimmed)
		}
		let directory = try await repository.browseLobbyistOrganizations(
			search: trimmed,
			sector: nil,
			page: 1,
			perPage: Self.directoryMatchLimit
		)
		guard let row = Self.bestDirectoryMatch(for: trimmed, rows: directory.rows) else {
			throw LobbyistOrganizationProfileLoadError.organizationNotFound(trimmed)
		}
		return try await execute(id: row.id)
	}

	private static func bestDirectoryMatch(
		for organizationName: String,
		rows: [LobbyistOrganizationDirectoryRow]
	) -> LobbyistOrganizationDirectoryRow? {
		rows.first { $0.name.caseInsensitiveCompare(organizationName) == .orderedSame } ?? rows.first
	}
}
