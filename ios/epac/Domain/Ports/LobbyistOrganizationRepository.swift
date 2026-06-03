protocol LobbyistOrganizationRepository: Sendable {
	func loadLobbyistOrganizationProfile(id: String) async throws -> LobbyistOrganization
	func browseLobbyistOrganizations(
		search: String?,
		sector: String?,
		page: Int,
		perPage: Int
	) async throws -> LobbyistOrganizationDirectory
}
