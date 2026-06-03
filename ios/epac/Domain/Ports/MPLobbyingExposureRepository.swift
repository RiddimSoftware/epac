protocol MPLobbyingExposureRepository: Sendable {
	func loadMPLobbyingExposure(
		memberID: Int,
		parliament: Int,
		window: MPLobbyingWindow,
		page: Int
	) async throws -> MPLobbyingExposure
}
