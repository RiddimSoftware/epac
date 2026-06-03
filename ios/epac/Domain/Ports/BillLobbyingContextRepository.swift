protocol BillLobbyingContextRepository: Sendable {
	func loadBillLobbyingContext(billID: String, windowMonths: Int) async throws -> BillLobbyingContext
}
