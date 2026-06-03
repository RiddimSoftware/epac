enum CabinetLobbyingDefaults {
	static let currentParliament = 45
}

struct LoadCabinetLobbyingOverview: Sendable {
	let repository: any CabinetLobbyingRepository

	func execute(parliament: Int = CabinetLobbyingDefaults.currentParliament) async throws -> CabinetLobbyingOverview {
		try await repository.loadCabinetLobbyingOverview(parliament: parliament)
	}
}
