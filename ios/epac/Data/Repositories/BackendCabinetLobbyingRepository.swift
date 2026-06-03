import Foundation

struct BackendCabinetLobbyingRepository: CabinetLobbyingRepository {
	private enum Constants {
		static let requestTimeout: TimeInterval = 20
		static let successStatusLowerBound = 200
		static let successStatusUpperBound = 300
		static let ministerPathPrefix = "api/v1/ministers"
		static let overviewPath = "api/v1/cabinet/lobbying-overview"

		static var successStatusCodes: Range<Int> {
			successStatusLowerBound..<successStatusUpperBound
		}
	}

	private let network: NetworkService
	private let baseURL: URL
	private let decoder: JSONDecoder

	init(
		network: NetworkService = .shared,
		baseURL: URL = BackendConfig.shared.baseURL,
		decoder: JSONDecoder = BackendCabinetLobbyingRepository.makeDecoder()
	) {
		self.network = network
		self.baseURL = baseURL
		self.decoder = decoder
	}

	func loadMinisterLobbyingByPortfolio(memberID: Int) async throws -> [MinisterPortfolioLobbyingPeriod] {
		let path = "\(Constants.ministerPathPrefix)/\(memberID)/lobbying-by-portfolio"
		let data = try await get(path: path, queryItems: [])
		let response = try decoder.decode(MinisterLobbyingByPortfolioResponse.self, from: data)
		return response.periods.map(\.domain)
	}

	func loadCabinetLobbyingOverview(parliament: Int) async throws -> CabinetLobbyingOverview {
		let queryItems = [URLQueryItem(name: "parliament", value: String(parliament))]
		let data = try await get(path: Constants.overviewPath, queryItems: queryItems)
		return try decoder.decode(CabinetLobbyingOverviewResponse.self, from: data).domain
	}

	private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
		guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
			throw URLError(.badURL)
		}
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}
		guard let url = components.url else {
			throw URLError(.badURL)
		}

		var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		let (data, response) = try await network.data(for: request)
		guard let http = response as? HTTPURLResponse,
		      Constants.successStatusCodes.contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}

	private static func makeDecoder() -> JSONDecoder {
		JSONDecoder()
	}

	fileprivate static func parseDate(_ value: String?) -> Date? {
		guard let value, !value.isEmpty else { return nil }
		return dateFormatter.date(from: value)
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
}

private struct MinisterLobbyingByPortfolioResponse: Decodable {
	let periods: [PortfolioPeriodDTO]

	enum CodingKeys: String, CodingKey {
		case periods
		case portfolioPeriods = "portfolio_periods"
		case portfolios
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let periods = try container.decodeIfPresent([PortfolioPeriodDTO].self, forKey: .periods) {
			self.periods = periods
		} else if let portfolios = try container.decodeIfPresent([PortfolioPeriodDTO].self, forKey: .portfolios) {
			self.periods = portfolios
		} else {
			self.periods = try container.decode([PortfolioPeriodDTO].self, forKey: .portfolioPeriods)
		}
	}
}

private struct PortfolioPeriodDTO: Decodable {
	let portfolioName: String
	let startDate: String?
	let endDate: String?
	let communications: [MinisterLobbyingCommunicationDTO]
	let topOrganizations: [CabinetLobbyingOrganizationDTO]

	enum CodingKeys: String, CodingKey {
		case portfolioName = "portfolio_name"
		case startDate = "start_date"
		case endDate = "end_date"
		case communications
		case topOrganizations = "top_organizations"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		portfolioName = try container.decode(String.self, forKey: .portfolioName)
		startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
		endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
		communications = try container.decodeIfPresent(
			[MinisterLobbyingCommunicationDTO].self,
			forKey: .communications
		) ?? []
		topOrganizations = try container.decodeIfPresent(
			[CabinetLobbyingOrganizationDTO].self,
			forKey: .topOrganizations
		) ?? []
	}

	var domain: MinisterPortfolioLobbyingPeriod {
		return MinisterPortfolioLobbyingPeriod(
			portfolioName: portfolioName,
			startDate: BackendCabinetLobbyingRepository.parseDate(startDate),
			endDate: BackendCabinetLobbyingRepository.parseDate(endDate),
			communications: communications.map(\.domain)
		)
	}
}

private struct MinisterLobbyingCommunicationDTO: Decodable {
	let id: String
	let organizationName: String
	let registrantName: String?
	let communicationDate: String?
	let subjectMatters: [String]
	let registrantType: String?
	let sourceURL: URL?
	let mandateMatch: Bool
	let communicationType: String?

	enum CodingKeys: String, CodingKey {
		case id
		case organizationName = "organization_name"
		case registrantName = "registrant_name"
		case communicationDate = "communication_date"
		case subjectMatters = "subject_matters"
		case registrantType = "registrant_type"
		case sourceURL = "source_url"
		case mandateMatch = "mandate_match"
		case communicationType = "communication_type"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let id = try? container.decode(String.self, forKey: .id) {
			self.id = id
		} else {
			id = String(try container.decode(Int.self, forKey: .id))
		}
		organizationName = try container.decode(String.self, forKey: .organizationName)
		registrantName = try container.decodeIfPresent(String.self, forKey: .registrantName)
		communicationDate = try container.decodeIfPresent(String.self, forKey: .communicationDate)
		subjectMatters = try container.decodeIfPresent([String].self, forKey: .subjectMatters) ?? []
		registrantType = try container.decodeIfPresent(String.self, forKey: .registrantType)
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
		mandateMatch = try container.decodeIfPresent(Bool.self, forKey: .mandateMatch) ?? false
		communicationType = try container.decodeIfPresent(String.self, forKey: .communicationType)
	}

	var domain: MinisterLobbyingCommunication {
		MinisterLobbyingCommunication(
			id: id,
			organizationName: organizationName,
			lobbyistName: registrantName ?? "",
			communicationDate: BackendCabinetLobbyingRepository.parseDate(communicationDate),
			subjectMatter: subjectMatters.joined(separator: ", "),
			registrantType: registrantType ?? "",
			registryURL: sourceURL ?? CabinetLobbyingSource.url,
			mandateMatch: mandateMatch,
			communicationType: communicationType
		)
	}
}

private struct CabinetLobbyingOverviewResponse: Decodable {
	let parliament: Int?
	let ministers: [CabinetLobbyingMinisterDTO]

	enum CodingKeys: String, CodingKey {
		case parliament
		case ministers
	}

	var domain: CabinetLobbyingOverview {
		let filters = Array(Set(ministers.flatMap(\.portfolioNames))).sorted()
		return CabinetLobbyingOverview(
			parliament: parliament,
			ministers: ministers.map(\.domain),
			portfolioFilters: filters,
			mostActiveOrganizations: Self.organizationSummaries(from: ministers)
		)
	}

	private static func organizationSummaries(
		from ministers: [CabinetLobbyingMinisterDTO]
	) -> [CabinetLobbyingOrganizationSummary] {
		var countsByPortfolio: [String: [String: Int]] = [:]
		for minister in ministers {
			for portfolio in minister.portfolios {
				let organizations = portfolio.topOrganizations.isEmpty
					? minister.topOrganizations
					: portfolio.topOrganizations
				for organization in organizations {
					countsByPortfolio[portfolio.portfolioName, default: [:]][organization.organizationName, default: 0] += organization.count
				}
			}
		}
		return countsByPortfolio.flatMap { portfolio, organizations in
			organizations.map { organization, count in
				CabinetLobbyingOrganizationSummary(
					portfolioName: portfolio,
					organizationName: organization,
					communicationCount: count
				)
			}
		}
		.sorted { lhs, rhs in
			if lhs.portfolioName == rhs.portfolioName {
				if lhs.communicationCount == rhs.communicationCount {
					return lhs.organizationName < rhs.organizationName
				}
				return lhs.communicationCount > rhs.communicationCount
			}
			return lhs.portfolioName < rhs.portfolioName
		}
	}
}

private struct CabinetLobbyingMinisterDTO: Decodable {
	let memberID: String
	let ministerName: String
	let portfolios: [PortfolioPeriodDTO]
	let totalCommunications: Int
	let mandateMatchCount: Int?
	let topOrganizations: [CabinetLobbyingOrganizationDTO]

	enum CodingKeys: String, CodingKey {
		case memberID = "member_id"
		case ministerName = "minister_name"
		case portfolios
		case totalCommunications = "total_communications"
		case mandateMatchCount = "mandate_match_count"
		case topOrganizations = "top_organizations"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let memberID = try? container.decode(String.self, forKey: .memberID) {
			self.memberID = memberID
		} else {
			memberID = String(try container.decode(Int.self, forKey: .memberID))
		}
		ministerName = try container.decode(String.self, forKey: .ministerName)
		portfolios = try container.decodeIfPresent([PortfolioPeriodDTO].self, forKey: .portfolios) ?? []
		totalCommunications = try container.decode(Int.self, forKey: .totalCommunications)
		mandateMatchCount = try container.decodeIfPresent(Int.self, forKey: .mandateMatchCount)
		topOrganizations = try container.decodeIfPresent(
			[CabinetLobbyingOrganizationDTO].self,
			forKey: .topOrganizations
		) ?? []
	}

	var portfolioNames: [String] {
		portfolios.map(\.portfolioName)
	}

	var domain: CabinetLobbyingMinisterSummary {
		let names = portfolioNames
		return CabinetLobbyingMinisterSummary(
			memberID: Int(memberID) ?? 0,
			ministerName: ministerName,
			portfolioName: names.joined(separator: ", "),
			portfolioNames: names,
			totalCommunications: totalCommunications,
			mandateMatchCount: mandateMatchCount ?? 0
		)
	}
}

private struct CabinetLobbyingOrganizationDTO: Decodable {
	let organizationName: String
	let count: Int

	enum CodingKeys: String, CodingKey {
		case organizationName = "organization_name"
		case count
	}
}
