struct LoadMPLobbyingExposure: Sendable {
	let repository: any MPLobbyingExposureRepository

	func execute(
		memberID: Int,
		parliament: Int = MPLobbyingExposureDefaults.currentParliament,
		window: MPLobbyingWindow = .threeMonths,
		page: Int = 1
	) async throws -> MPLobbyingExposure {
		try await repository.loadMPLobbyingExposure(
			memberID: memberID,
			parliament: parliament,
			window: window,
			page: page
		)
	}
}
