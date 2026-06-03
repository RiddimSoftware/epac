import Foundation

enum BillLobbyingContextDefaults {
	static let windowMonths = 12
}

struct BillLobbyingContext: Equatable, Sendable {
	let billID: String
	let windowMonths: Int
	let windowStartDate: Date?
	let windowEndDate: Date?
	let subjectTags: [String]
	let totalCommunications: Int
	let organizations: [BillLobbyingOrganization]
	let topOrganizations: [BillLobbyingOrganization]
	let sourceURL: URL

	var hasCommunications: Bool {
		totalCommunications > 0
	}

	static let empty = BillLobbyingContext(
		billID: "",
		windowMonths: BillLobbyingContextDefaults.windowMonths,
		windowStartDate: nil,
		windowEndDate: nil,
		subjectTags: [],
		totalCommunications: 0,
		organizations: [],
		topOrganizations: [],
		sourceURL: CabinetLobbyingSource.url
	)
}

struct BillLobbyingOrganization: Identifiable, Equatable, Sendable {
	let id: String
	let name: String
	let communicationCount: Int

	init(id: String? = nil, name: String, communicationCount: Int) {
		self.id = id ?? name
		self.name = name
		self.communicationCount = communicationCount
	}
}
