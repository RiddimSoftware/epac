struct LoadBillLobbyingContext: Sendable {
	let repository: any BillLobbyingContextRepository

	func execute(
		billID: String,
		windowMonths: Int = BillLobbyingContextDefaults.windowMonths
	) async throws -> BillLobbyingContext {
		try await repository.loadBillLobbyingContext(billID: billID, windowMonths: windowMonths)
	}
}
