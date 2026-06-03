import Foundation

struct BackendBillLobbyingContextRepository: BillLobbyingContextRepository {
	fileprivate enum Constants {
		static let requestTimeout: TimeInterval = 20
		static let successStatusLowerBound = 200
		static let successStatusUpperBound = 300
		static let pathPrefix = "api/v1/bills"
		static let pathSuffix = "lobbying-context"
		static let topOrganizationsLimit = 3

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

	func loadBillLobbyingContext(
		billID: String,
		windowMonths: Int = BillLobbyingContextDefaults.windowMonths
	) async throws -> BillLobbyingContext {
		let path = "\(Constants.pathPrefix)/\(billID)/\(Constants.pathSuffix)"
		let queryItems = [URLQueryItem(name: "window_months", value: String(windowMonths))]
		let data = try await get(path: path, queryItems: queryItems)
		return try decoder.decode(BillLobbyingContextResponse.self, from: data).domain
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

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
}

private struct BillLobbyingContextResponse: Decodable {
	let legisInfoID: String
	let windowMonths: Int
	let windowStartDate: String?
	let windowEndDate: String?
	let subjectTags: [String]
	let totalCommunications: Int
	let countByOrganization: [BillLobbyingOrganizationDTO]
	let topOrganizations: [BillLobbyingOrganizationDTO]
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case legisInfoID = "legisinfo_id"
		case windowMonths = "window_months"
		case windowStartDate = "window_start_date"
		case windowEndDate = "window_end_date"
		case subjectTags = "subject_tags"
		case totalCommunications = "total_communications"
		case countByOrganization = "count_by_organization"
		case topOrganizations = "top_organizations"
		case sourceURL = "source_url"
	}

	var domain: BillLobbyingContext {
		let fallbackOrganizations = countByOrganization
			.sorted { lhs, rhs in
				if lhs.count == rhs.count {
					return lhs.organizationName < rhs.organizationName
				}
				return lhs.count > rhs.count
			}
			.prefix(BackendBillLobbyingContextRepository.Constants.topOrganizationsLimit)

		let topRows = topOrganizations.isEmpty ? Array(fallbackOrganizations) : topOrganizations
		return BillLobbyingContext(
			billID: legisInfoID,
			windowMonths: windowMonths,
			windowStartDate: BackendBillLobbyingContextRepository.parseDate(windowStartDate),
			windowEndDate: BackendBillLobbyingContextRepository.parseDate(windowEndDate),
			subjectTags: subjectTags,
			totalCommunications: totalCommunications,
			organizations: countByOrganization.map(\.domain),
			topOrganizations: Array(topRows.prefix(BackendBillLobbyingContextRepository.Constants.topOrganizationsLimit))
				.map(\.domain),
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}
}

private struct BillLobbyingOrganizationDTO: Decodable {
	let organizationName: String
	let count: Int

	enum CodingKeys: String, CodingKey {
		case organizationName = "organization_name"
		case count
	}

	var domain: BillLobbyingOrganization {
		BillLobbyingOrganization(name: organizationName, communicationCount: count)
	}
}
