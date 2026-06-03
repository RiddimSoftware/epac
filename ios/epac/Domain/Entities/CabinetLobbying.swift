import Foundation

enum CabinetLobbyingSource {
	static let citation = "Source: Office of the Commissioner of Lobbying (OCL)"
	static let url = URL(string: "https://lobbycanada.gc.ca/en/open-data/")!
}

struct MinisterLobbyingCommunication: Identifiable, Equatable, Sendable {
	let id: String
	let organizationName: String
	let lobbyistName: String
	let communicationDate: Date?
	let subjectMatter: String
	let registrantType: String
	let registryURL: URL
	let mandateMatch: Bool
	let communicationType: String?
}

struct MinisterPortfolioLobbyingPeriod: Identifiable, Equatable, Sendable {
	let portfolioName: String
	let startDate: Date?
	let endDate: Date?
	let communications: [MinisterLobbyingCommunication]

	var id: String {
		[
			portfolioName,
			startDate?.formatted(.iso8601.year().month().day()) ?? "unknown-start",
			endDate?.formatted(.iso8601.year().month().day()) ?? "current"
		].joined(separator: "|")
	}

	var communicationCount: Int {
		communications.count
	}
}

struct CabinetLobbyingMinisterSummary: Identifiable, Equatable, Sendable {
	let memberID: Int
	let ministerName: String
	let portfolioName: String
	let portfolioNames: [String]
	let totalCommunications: Int
	let mandateMatchCount: Int

	init(
		memberID: Int,
		ministerName: String,
		portfolioName: String,
		portfolioNames: [String]? = nil,
		totalCommunications: Int,
		mandateMatchCount: Int
	) {
		self.memberID = memberID
		self.ministerName = ministerName
		self.portfolioName = portfolioName
		self.portfolioNames = portfolioNames ?? [portfolioName]
		self.totalCommunications = totalCommunications
		self.mandateMatchCount = mandateMatchCount
	}

	var id: Int {
		memberID
	}
}

struct CabinetLobbyingOrganizationSummary: Identifiable, Equatable, Sendable {
	let portfolioName: String
	let organizationName: String
	let communicationCount: Int

	var id: String {
		"\(portfolioName)|\(organizationName)"
	}
}

struct CabinetLobbyingOverview: Equatable, Sendable {
	let parliament: Int?
	let ministers: [CabinetLobbyingMinisterSummary]
	let portfolioFilters: [String]
	let mostActiveOrganizations: [CabinetLobbyingOrganizationSummary]

	static let empty = CabinetLobbyingOverview(
		parliament: nil,
		ministers: [],
		portfolioFilters: [],
		mostActiveOrganizations: []
	)
}
