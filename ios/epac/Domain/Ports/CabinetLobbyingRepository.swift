protocol CabinetLobbyingRepository: Sendable {
	func loadMinisterLobbyingByPortfolio(memberID: Int) async throws -> [MinisterPortfolioLobbyingPeriod]
	func loadCabinetLobbyingOverview(parliament: Int) async throws -> CabinetLobbyingOverview
}
