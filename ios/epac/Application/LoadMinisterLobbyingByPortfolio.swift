struct LoadMinisterLobbyingByPortfolio: Sendable {
	let repository: any CabinetLobbyingRepository

	func execute(memberID: Int) async throws -> [MinisterPortfolioLobbyingPeriod] {
		try await repository.loadMinisterLobbyingByPortfolio(memberID: memberID)
	}
}
