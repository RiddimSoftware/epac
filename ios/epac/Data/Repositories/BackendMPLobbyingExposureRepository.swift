import Foundation

struct BackendMPLobbyingExposureRepository: MPLobbyingExposureRepository {
	private enum Constants {
		static let requestTimeout: TimeInterval = 20
		static let successStatusLowerBound = 200
		static let successStatusUpperBound = 300
		static let pathPrefix = "api/v1/members"
		static let pathSuffix = "lobbying-exposure"

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
		decoder: JSONDecoder = JSONDecoder()
	) {
		self.network = network
		self.baseURL = baseURL
		self.decoder = decoder
	}

	func loadMPLobbyingExposure(
		memberID: Int,
		parliament: Int,
		window: MPLobbyingWindow,
		page: Int
	) async throws -> MPLobbyingExposure {
		let path = "\(Constants.pathPrefix)/\(memberID)/\(Constants.pathSuffix)"
		let queryItems = [
			URLQueryItem(name: "parliament", value: String(parliament)),
			URLQueryItem(name: "window", value: window.rawValue),
			URLQueryItem(name: "page", value: String(page))
		]
		let data = try await get(path: path, queryItems: queryItems)
		return try decoder.decode(MPLobbyingExposureResponse.self, from: data).domain
	}

	private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
		guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
			throw URLError(.badURL)
		}
		components.queryItems = queryItems
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

	fileprivate static func parseDate(_ value: String?) -> Date? {
		guard let value, !value.isEmpty else { return nil }
		return dateFormatter.date(from: value)
	}

	fileprivate static func parseDateTime(_ value: String?) -> Date? {
		guard let value, !value.isEmpty else { return nil }
		let fractionalSecondsFormatter = ISO8601DateFormatter()
		fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = fractionalSecondsFormatter.date(from: value) {
			return date
		}

		let standardFormatter = ISO8601DateFormatter()
		standardFormatter.formatOptions = [.withInternetDateTime]
		return standardFormatter.date(from: value)
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

private struct MPLobbyingExposureResponse: Decodable {
	let memberID: String
	let parliament: Int
	let window: MPLobbyingWindow
	let page: Int
	let perPage: Int
	let total: Int
	let pages: Int
	let summary: MPLobbyingSummaryDTO
	let subjectBreakdown: [MPLobbyingSubjectDistributionDTO]
	let timeline: [MPLobbyingTimelineEntryDTO]
	let citation: String?
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case memberID = "member_id"
		case parliament
		case window
		case page
		case perPage = "per_page"
		case total
		case pages
		case summary
		case subjectBreakdown = "subject_breakdown"
		case timeline
		case citation
		case sourceURL = "source_url"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let value = try? container.decode(String.self, forKey: .memberID) {
			memberID = value
		} else {
			memberID = String(try container.decode(Int.self, forKey: .memberID))
		}
		parliament = try container.decode(Int.self, forKey: .parliament)
		window = try container.decode(MPLobbyingWindow.self, forKey: .window)
		page = try container.decode(Int.self, forKey: .page)
		perPage = try container.decode(Int.self, forKey: .perPage)
		total = try container.decode(Int.self, forKey: .total)
		pages = try container.decode(Int.self, forKey: .pages)
		summary = try container.decode(MPLobbyingSummaryDTO.self, forKey: .summary)
		subjectBreakdown = try container.decodeIfPresent(
			[MPLobbyingSubjectDistributionDTO].self,
			forKey: .subjectBreakdown
		) ?? []
		timeline = try container.decodeIfPresent([MPLobbyingTimelineEntryDTO].self, forKey: .timeline) ?? []
		citation = try container.decodeIfPresent(String.self, forKey: .citation)
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
	}

	var domain: MPLobbyingExposure {
		MPLobbyingExposure(
			memberID: memberID,
			parliament: parliament,
			window: window,
			page: page,
			perPage: perPage,
			total: total,
			pages: pages,
			summary: summary.domain,
			subjectBreakdown: subjectBreakdown.map(\.domain),
			timeline: timeline.map(\.domain),
			citation: citation ?? CabinetLobbyingSource.citation,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}
}

private struct MPLobbyingSummaryDTO: Decodable {
	let memberID: String
	let parliament: Int
	let quarterStart: String?
	let window: MPLobbyingWindow
	let totalCommunicationCount: Int
	let uniqueOrganizationsCount: Int
	let mostFrequentSubjectMatter: String?
	let topOrganizations: [TopLobbyingOrganizationDTO]
	let trendVsPreviousParliament: MPLobbyingTrendDTO
	let partyAverageCommunications: Double
	let nationalAverageCommunications: Double
	let citation: String?
	let updatedAt: String?

	enum CodingKeys: String, CodingKey {
		case memberID = "member_id"
		case parliament
		case quarterStart = "quarter_start"
		case window
		case totalCommunicationCount = "total_communication_count"
		case uniqueOrganizationsCount = "unique_organizations_count"
		case mostFrequentSubjectMatter = "most_frequent_subject_matter"
		case topOrganizations = "top_organizations"
		case trendVsPreviousParliament = "trend_vs_previous_parliament"
		case partyAverageCommunications = "party_average_communications"
		case nationalAverageCommunications = "national_average_communications"
		case citation
		case updatedAt = "updated_at"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let value = try? container.decode(String.self, forKey: .memberID) {
			memberID = value
		} else {
			memberID = String(try container.decode(Int.self, forKey: .memberID))
		}
		parliament = try container.decode(Int.self, forKey: .parliament)
		quarterStart = try container.decodeIfPresent(String.self, forKey: .quarterStart)
		window = try container.decode(MPLobbyingWindow.self, forKey: .window)
		totalCommunicationCount = try container.decode(Int.self, forKey: .totalCommunicationCount)
		uniqueOrganizationsCount = try container.decode(Int.self, forKey: .uniqueOrganizationsCount)
		mostFrequentSubjectMatter = try container.decodeIfPresent(String.self, forKey: .mostFrequentSubjectMatter)
		topOrganizations = try container.decodeIfPresent([TopLobbyingOrganizationDTO].self, forKey: .topOrganizations) ?? []
		trendVsPreviousParliament = try container.decode(MPLobbyingTrendDTO.self, forKey: .trendVsPreviousParliament)
		partyAverageCommunications = try container.decode(Double.self, forKey: .partyAverageCommunications)
		nationalAverageCommunications = try container.decode(Double.self, forKey: .nationalAverageCommunications)
		citation = try container.decodeIfPresent(String.self, forKey: .citation)
		updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
	}

	var domain: MPLobbyingSummary {
		MPLobbyingSummary(
			memberID: memberID,
			parliament: parliament,
			quarterStart: BackendMPLobbyingExposureRepository.parseDateTime(quarterStart),
			window: window,
			totalCommunicationCount: totalCommunicationCount,
			uniqueOrganizationsCount: uniqueOrganizationsCount,
			mostFrequentSubjectMatter: mostFrequentSubjectMatter,
			topOrganizations: topOrganizations.map(\.domain),
			trendVsPreviousParliament: trendVsPreviousParliament.domain,
			partyAverageCommunications: partyAverageCommunications,
			nationalAverageCommunications: nationalAverageCommunications,
			citation: citation ?? CabinetLobbyingSource.citation,
			updatedAt: BackendMPLobbyingExposureRepository.parseDateTime(updatedAt)
		)
	}
}

private struct TopLobbyingOrganizationDTO: Decodable {
	let name: String
	let sector: String?
	let communicationCount: Int

	enum CodingKeys: String, CodingKey {
		case name
		case sector
		case communicationCount = "communication_count"
	}

	var domain: MPLobbyingTopOrganization {
		MPLobbyingTopOrganization(
			name: name,
			sector: sector,
			communicationCount: communicationCount
		)
	}
}

private struct MPLobbyingTrendDTO: Decodable {
	let currentParliament: Int
	let previousParliament: Int
	let delta: Int

	enum CodingKeys: String, CodingKey {
		case currentParliament = "current_parliament"
		case previousParliament = "previous_parliament"
		case delta
	}

	var domain: MPLobbyingTrend {
		MPLobbyingTrend(
			currentParliament: currentParliament,
			previousParliament: previousParliament,
			delta: delta
		)
	}
}

private struct MPLobbyingSubjectDistributionDTO: Decodable {
	let subjectMatter: String
	let communicationCount: Int

	enum CodingKeys: String, CodingKey {
		case subjectMatter = "subject_matter"
		case communicationCount = "communication_count"
	}

	var domain: MPLobbyingSubjectDistribution {
		MPLobbyingSubjectDistribution(
			subjectMatter: subjectMatter,
			communicationCount: communicationCount
		)
	}
}

private struct MPLobbyingTimelineEntryDTO: Decodable {
	let communicationID: String
	let date: String?
	let organizationName: String
	let organizationSector: String?
	let subjectMatter: String
	let communicationType: String
	let billCrossReference: BillCrossReferenceDTO?
	let citation: String?
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case communicationID = "communication_id"
		case date
		case organizationName = "organization_name"
		case organizationSector = "organization_sector"
		case subjectMatter = "subject_matter"
		case communicationType = "communication_type"
		case billCrossReference = "bill_cross_reference"
		case citation
		case sourceURL = "source_url"
	}

	var domain: MPLobbyingTimelineEntry {
		MPLobbyingTimelineEntry(
			communicationID: communicationID,
			date: BackendMPLobbyingExposureRepository.parseDate(date),
			organizationName: organizationName,
			organizationSector: organizationSector,
			subjectMatter: subjectMatter,
			communicationType: communicationType,
			billCrossReference: billCrossReference?.domain,
			citation: citation ?? CabinetLobbyingSource.citation,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}
}

private struct BillCrossReferenceDTO: Decodable {
	let billNumber: String
	let billTitle: String?
	let url: URL
	let mappingConfidence: Double

	enum CodingKeys: String, CodingKey {
		case billNumber = "bill_number"
		case billTitle = "bill_title"
		case url
		case mappingConfidence = "mapping_confidence"
	}

	var domain: MPLobbyingBillCrossReference {
		MPLobbyingBillCrossReference(
			billNumber: billNumber,
			billTitle: billTitle,
			url: url,
			mappingConfidence: mappingConfidence
		)
	}
}
