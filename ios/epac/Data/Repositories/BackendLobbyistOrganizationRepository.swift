import Foundation

struct BackendLobbyistOrganizationRepository: LobbyistOrganizationRepository {
	private enum Constants {
		static let requestTimeout: TimeInterval = 20
		static let successStatusLowerBound = 200
		static let successStatusUpperBound = 300
		static let organizationsPath = "api/v1/lobbying/organizations"

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

	func loadLobbyistOrganizationProfile(id: String) async throws -> LobbyistOrganization {
		let data = try await get(path: "\(Constants.organizationsPath)/\(id)", queryItems: [])
		return try decoder.decode(LobbyistOrganizationProfileDTO.self, from: data).domain
	}

	func browseLobbyistOrganizations(
		search: String?,
		sector: String?,
		page: Int,
		perPage: Int
	) async throws -> LobbyistOrganizationDirectory {
		var queryItems = [
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "per_page", value: String(perPage))
		]
		if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			queryItems.append(URLQueryItem(name: "search", value: search))
		}
		if let sector, !sector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			queryItems.append(URLQueryItem(name: "sector", value: sector))
		}
		let data = try await get(path: Constants.organizationsPath, queryItems: queryItems)
		return try decoder.decode(LobbyistOrganizationDirectoryDTO.self, from: data).domain
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

private struct LobbyistOrganizationDirectoryDTO: Decodable {
	let page: Int
	let perPage: Int
	let citation: String?
	let sourceURL: URL?
	let rows: [LobbyistOrganizationDirectoryRowDTO]

	enum CodingKeys: String, CodingKey {
		case page
		case perPage = "per_page"
		case citation
		case sourceURL = "source_url"
		case rows
	}

	var domain: LobbyistOrganizationDirectory {
		LobbyistOrganizationDirectory(
			page: page,
			perPage: perPage,
			citation: citation ?? CabinetLobbyingSource.citation,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url,
			rows: rows.map(\.domain)
		)
	}
}

private struct LobbyistOrganizationDirectoryRowDTO: Decodable {
	let id: String
	let name: String
	let type: LobbyistOrganizationType
	let sector: String?
	let communicationVolumeCurrentParliament: Int

	enum CodingKeys: String, CodingKey {
		case id
		case name
		case type
		case sector
		case communicationVolumeCurrentParliament = "communication_volume_current_parliament"
	}

	var domain: LobbyistOrganizationDirectoryRow {
		LobbyistOrganizationDirectoryRow(
			id: id,
			name: name,
			type: type,
			sector: sector,
			communicationVolumeCurrentParliament: communicationVolumeCurrentParliament
		)
	}
}

private struct LobbyistOrganizationProfileDTO: Decodable {
	let id: String
	let oclOrganizationID: String?
	let name: String
	let type: LobbyistOrganizationType
	let sector: String?
	let registeredLobbyists: [RegisteredLobbyistDTO]
	let activeSubjectMatters: [String]
	let communicationVolume: LobbyistOrganizationCommunicationVolumeDTO
	let topDPOHsContacted: [LobbyistOrganizationDPOHContactDTO]
	let registrationStatus: LobbyistRegistrationStatus?
	let registrations: [LobbyistRegistrationDTO]
	let recentCommunications: [LobbyistOrganizationCommunicationDTO]
	let subjectMatters: [LobbyistOrganizationSubjectMatterDTO]
	let citation: String?
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case id
		case oclOrganizationID = "ocl_organization_id"
		case name
		case type
		case sector
		case registeredLobbyists = "registered_lobbyists"
		case activeSubjectMatters = "active_subject_matters"
		case communicationVolume = "communication_volume"
		case topDPOHsContacted = "top_dpohs_contacted"
		case registrationStatus = "registration_status"
		case registrations
		case recentCommunications = "recent_communications"
		case subjectMatters = "subject_matters"
		case citation
		case sourceURL = "source_url"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		oclOrganizationID = try container.decodeIfPresent(String.self, forKey: .oclOrganizationID)
		name = try container.decode(String.self, forKey: .name)
		type = try container.decode(LobbyistOrganizationType.self, forKey: .type)
		sector = try container.decodeIfPresent(String.self, forKey: .sector)
		registeredLobbyists = try container.decodeIfPresent([RegisteredLobbyistDTO].self, forKey: .registeredLobbyists) ?? []
		activeSubjectMatters = try container.decodeIfPresent([String].self, forKey: .activeSubjectMatters) ?? []
		communicationVolume = try container.decode(
			LobbyistOrganizationCommunicationVolumeDTO.self,
			forKey: .communicationVolume
		)
		topDPOHsContacted = try container.decodeIfPresent(
			[LobbyistOrganizationDPOHContactDTO].self,
			forKey: .topDPOHsContacted
		) ?? []
		registrationStatus = try container.decodeIfPresent(
			LobbyistRegistrationStatus.self,
			forKey: .registrationStatus
		)
		registrations = try container.decodeIfPresent([LobbyistRegistrationDTO].self, forKey: .registrations) ?? []
		recentCommunications = try container.decodeIfPresent(
			[LobbyistOrganizationCommunicationDTO].self,
			forKey: .recentCommunications
		) ?? []
		subjectMatters = try container.decodeIfPresent(
			[LobbyistOrganizationSubjectMatterDTO].self,
			forKey: .subjectMatters
		) ?? []
		citation = try container.decodeIfPresent(String.self, forKey: .citation)
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
	}

	var domain: LobbyistOrganization {
		LobbyistOrganization(
			id: id,
			oclOrganizationID: oclOrganizationID,
			name: name,
			type: type,
			sector: sector,
			registeredLobbyists: registeredLobbyists.map(\.domain),
			activeSubjectMatters: activeSubjectMatters,
			communicationVolume: communicationVolume.domain,
			topDPOHsContacted: topDPOHsContacted.map(\.domain),
			registrationStatus: registrationStatus ?? inferredRegistrationStatus,
			registrations: registrations.map(\.domain),
			recentCommunications: recentCommunications.map(\.domain),
			subjectMatters: subjectMatters.map(\.domain),
			citation: citation ?? CabinetLobbyingSource.citation,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}

	private var inferredRegistrationStatus: LobbyistRegistrationStatus {
		registrations.contains { $0.status == .active } ? .active : .expired
	}
}

private struct RegisteredLobbyistDTO: Decodable {
	let name: String
	let kind: LobbyistRegistrationKind

	var domain: RegisteredLobbyist {
		RegisteredLobbyist(name: name, kind: kind)
	}
}

private struct LobbyistOrganizationCommunicationVolumeDTO: Decodable {
	let currentParliament: Int
	let priorParliament: Int

	enum CodingKeys: String, CodingKey {
		case currentParliament = "current_parliament"
		case priorParliament = "prior_parliament"
	}

	var domain: LobbyistOrganizationCommunicationVolume {
		LobbyistOrganizationCommunicationVolume(
			currentParliament: currentParliament,
			priorParliament: priorParliament
		)
	}
}

private struct LobbyistOrganizationDPOHContactDTO: Decodable {
	let memberID: String?
	let name: String
	let institution: String
	let count: Int

	enum CodingKeys: String, CodingKey {
		case memberID = "member_id"
		case name
		case institution
		case count
	}

	var domain: LobbyistOrganizationDPOHContact {
		LobbyistOrganizationDPOHContact(
			memberID: memberID,
			name: name,
			institution: institution,
			count: count
		)
	}
}

private struct LobbyistRegistrationDTO: Decodable {
	let id: String
	let status: LobbyistRegistrationStatus
	let kind: LobbyistRegistrationKind
	let subjectMatters: [String]
	let targetedInstitutions: [String]
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case id
		case status
		case kind
		case subjectMatters = "subject_matters"
		case targetedInstitutions = "targeted_institutions"
		case sourceURL = "source_url"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		status = try container.decode(LobbyistRegistrationStatus.self, forKey: .status)
		kind = try container.decode(LobbyistRegistrationKind.self, forKey: .kind)
		subjectMatters = try container.decodeIfPresent([String].self, forKey: .subjectMatters) ?? []
		targetedInstitutions = try container.decodeIfPresent([String].self, forKey: .targetedInstitutions) ?? []
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
	}

	var domain: LobbyistRegistration {
		LobbyistRegistration(
			id: id,
			status: status,
			kind: kind,
			subjectMatters: subjectMatters,
			targetedInstitutions: targetedInstitutions,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}
}

private struct LobbyistOrganizationCommunicationDTO: Decodable {
	let id: String
	let date: String?
	let dpohMemberID: String?
	let dpohName: String
	let institution: String
	let subjectMatters: [String]
	let sourceURL: URL?

	enum CodingKeys: String, CodingKey {
		case id
		case date
		case dpohMemberID = "dpoh_member_id"
		case dpohName = "dpoh_name"
		case institution
		case subjectMatters = "subject_matters"
		case sourceURL = "source_url"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		date = try container.decodeIfPresent(String.self, forKey: .date)
		dpohMemberID = try container.decodeIfPresent(String.self, forKey: .dpohMemberID)
		dpohName = try container.decode(String.self, forKey: .dpohName)
		institution = try container.decode(String.self, forKey: .institution)
		subjectMatters = try container.decodeIfPresent([String].self, forKey: .subjectMatters) ?? []
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
	}

	var domain: LobbyistOrganizationCommunication {
		LobbyistOrganizationCommunication(
			id: id,
			date: BackendLobbyistOrganizationRepository.parseDate(date),
			dpohMemberID: dpohMemberID,
			dpohName: dpohName,
			institution: institution,
			subjectMatters: subjectMatters,
			sourceURL: sourceURL ?? CabinetLobbyingSource.url
		)
	}
}

private struct LobbyistOrganizationSubjectMatterDTO: Decodable {
	let subjectMatter: String
	let communicationCount: Int
	let topicSlug: String?

	enum CodingKeys: String, CodingKey {
		case subjectMatter = "subject_matter"
		case communicationCount = "communication_count"
		case topicSlug = "topic_slug"
	}

	var domain: LobbyistOrganizationSubjectMatter {
		LobbyistOrganizationSubjectMatter(
			subjectMatter: subjectMatter,
			communicationCount: communicationCount,
			topicSlug: topicSlug
		)
	}
}
