//
//  BackendMPBiographyRepository.swift
//  epac
//

import Foundation

@MainActor
struct BackendMPBiographyRepository: MPBiographyRepository {
	fileprivate enum Constants {
		static let requestTimeout: TimeInterval = 20
		static let successStatusLowerBound = 200
		static let successStatusUpperBound = 300
		static let pathPrefix = "api/v1/members"

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

	func loadBiography(memberID: Int) async throws -> MemberBiography {
		let path = "\(Constants.pathPrefix)/\(memberID)"
		let data = try await get(path: path)
		return try decoder.decode(MemberProfileBiographyResponse.self, from: data).domain
	}

	private func get(path: String) async throws -> Data {
		let url = baseURL.appending(path: path)
		var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		let (data, response) = try await network.data(for: request)
		guard let http = response as? HTTPURLResponse,
		      Constants.successStatusCodes.contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}
}

private struct MemberProfileBiographyResponse: Decodable {
	let member: MemberBiographyDTO

	var domain: MemberBiography {
		member.domain
	}
}

private struct MemberBiographyDTO: Decodable {
	let sourceURL: URL?
	let profileURL: URL?
	let fromDate: String?
	let toDate: String?
	let biography: BiographyDetailsDTO?
	let pmbSponsorships: [SponsoredBillDTO]
	let sponsoredBills: [SponsoredBillDTO]
	let yearsServed: [ServicePeriodDTO]
	let previousRoles: [ParliamentaryRoleDTO]
	let education: [String]
	let professionalBackground: [String]

	enum CodingKeys: String, CodingKey {
		case sourceURL = "source_url"
		case profileURL = "profile_url"
		case fromDate = "from_date"
		case toDate = "to_date"
		case biography
		case pmbSponsorships = "pmb_sponsorships"
		case sponsoredBills = "sponsored_bills"
		case privateMembersBillsSponsored = "private_members_bills_sponsored"
		case yearsServed = "years_served"
		case servicePeriods = "service_periods"
		case parliamentaryCareerHistory = "parliamentary_career_history"
		case previousRoles = "previous_roles"
		case parliamentaryRoles = "parliamentary_roles"
		case education
		case professionalBackground = "professional_background"
		case background
		case career
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
		profileURL = try container.decodeIfPresent(URL.self, forKey: .profileURL)
		fromDate = try container.decodeIfPresent(String.self, forKey: .fromDate)
		toDate = try container.decodeIfPresent(String.self, forKey: .toDate)
		biography = try container.decodeIfPresent(BiographyDetailsDTO.self, forKey: .biography)
		pmbSponsorships = container.decodeArray([.pmbSponsorships])
		sponsoredBills = container.decodeArray([.sponsoredBills, .privateMembersBillsSponsored])
		yearsServed = container.decodeArray([.yearsServed, .servicePeriods, .parliamentaryCareerHistory])
		previousRoles = container.decodeArray([.previousRoles, .parliamentaryRoles])
		education = container.decodeStringList([.education])
		professionalBackground = container.decodeStringList([.professionalBackground, .background, .career])
	}

	var domain: MemberBiography {
		let details = biography
		let allBills = pmbSponsorships + sponsoredBills + (details?.sponsoredBills ?? [])
		return MemberBiography(
			yearsServed: yearsServed.map(\.domain) + (details?.yearsServed.map(\.domain) ?? []),
			previousRoles: previousRoles.map(\.domain) + (details?.previousRoles.map(\.domain) ?? []),
			education: education + (details?.education ?? []),
			professionalBackground: professionalBackground + (details?.professionalBackground ?? []),
			sponsoredBills: allBills.map(\.domain),
			sourceURL: details?.sourceURL ?? sourceURL,
			officialProfileURL: profileURL ?? details?.sourceURL ?? sourceURL
		)
	}
}

private struct BiographyDetailsDTO: Decodable {
	let sourceURL: URL?
	let yearsServed: [ServicePeriodDTO]
	let previousRoles: [ParliamentaryRoleDTO]
	let education: [String]
	let professionalBackground: [String]
	let sponsoredBills: [SponsoredBillDTO]

	enum CodingKeys: String, CodingKey {
		case sourceURL = "source_url"
		case yearsServed = "years_served"
		case servicePeriods = "service_periods"
		case parliamentaryCareerHistory = "parliamentary_career_history"
		case previousRoles = "previous_roles"
		case parliamentaryRoles = "parliamentary_roles"
		case education
		case professionalBackground = "professional_background"
		case background
		case career
		case summary
		case sponsoredBills = "sponsored_bills"
		case pmbSponsorships = "pmb_sponsorships"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
		yearsServed = container.decodeArray([.yearsServed, .servicePeriods, .parliamentaryCareerHistory])
		previousRoles = container.decodeArray([.previousRoles, .parliamentaryRoles])
		education = container.decodeStringList([.education])
		let explicitBackground = container.decodeStringList([.professionalBackground, .background, .career])
		professionalBackground = explicitBackground.isEmpty ? container.decodeStringList([.summary]) : explicitBackground
		sponsoredBills = container.decodeArray([.sponsoredBills, .pmbSponsorships])
	}
}

private struct ServicePeriodDTO: Decodable {
	let label: String
	let fromDate: String?
	let toDate: String?

	enum CodingKeys: String, CodingKey {
		case label
		case title
		case parliament
		case session
		case fromDate = "from_date"
		case startDate = "start_date"
		case toDate = "to_date"
		case endDate = "end_date"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let explicitLabel = try container.decodeIfPresent(String.self, forKey: .label) ??
			container.decodeIfPresent(String.self, forKey: .title)
		let parliament = try container.decodeIfPresent(Int.self, forKey: .parliament)
		let session = try container.decodeIfPresent(Int.self, forKey: .session)
		if let explicitLabel, !explicitLabel.isEmpty {
			label = explicitLabel
		} else if let parliament, let session {
			label = "\(parliament)-\(session)"
		} else if let parliament {
			label = "Parliament \(parliament)"
		} else {
			label = ""
		}
		fromDate = try container.decodeIfPresent(String.self, forKey: .fromDate) ??
			container.decodeIfPresent(String.self, forKey: .startDate)
		toDate = try container.decodeIfPresent(String.self, forKey: .toDate) ??
			container.decodeIfPresent(String.self, forKey: .endDate)
	}

	var domain: ParliamentaryServicePeriod {
		ParliamentaryServicePeriod(
			id: [label, fromDate, toDate].compactMap { $0 }.joined(separator: "|"),
			label: label,
			fromDate: fromDate,
			toDate: toDate
		)
	}
}

private struct ParliamentaryRoleDTO: Decodable {
	let title: String
	let organization: String?
	let startDate: String?
	let endDate: String?

	enum CodingKeys: String, CodingKey {
		case title
		case role
		case organization
		case committee
		case startDate = "start_date"
		case fromDate = "from_date"
		case endDate = "end_date"
		case toDate = "to_date"
		case dateRange = "date_range"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		title = (try container.decodeIfPresent(String.self, forKey: .title) ??
			container.decodeIfPresent(String.self, forKey: .role) ?? "")
		organization = try container.decodeIfPresent(String.self, forKey: .organization) ??
			container.decodeIfPresent(String.self, forKey: .committee)
		if let dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange), !dateRange.isEmpty {
			startDate = dateRange
			endDate = nil
		} else {
			startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ??
				container.decodeIfPresent(String.self, forKey: .fromDate)
			endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ??
				container.decodeIfPresent(String.self, forKey: .toDate)
		}
	}

	var domain: ParliamentaryRole {
		ParliamentaryRole(
			id: [title, organization, startDate, endDate].compactMap { $0 }.joined(separator: "|"),
			title: title,
			organization: organization,
			startDate: startDate,
			endDate: endDate
		)
	}
}

private struct SponsoredBillDTO: Decodable {
	let id: String?
	let number: String
	let title: String
	let relationship: String
	let legisInfoURL: URL?

	enum CodingKeys: String, CodingKey {
		case id
		case number
		case billNumber = "bill_number"
		case title
		case relationship
		case legisInfoURL = "legis_info_url"
		case legisinfoURL = "legisinfo_url"
		case url
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(String.self, forKey: .id)
		number = try container.decodeIfPresent(String.self, forKey: .number) ??
			container.decodeIfPresent(String.self, forKey: .billNumber) ?? ""
		title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
		relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? "sponsored"
		legisInfoURL = try container.decodeIfPresent(URL.self, forKey: .legisInfoURL) ??
			container.decodeIfPresent(URL.self, forKey: .legisinfoURL) ??
			container.decodeIfPresent(URL.self, forKey: .url)
	}

	var domain: SponsoredBillReference {
		SponsoredBillReference(
			id: id ?? [relationship, number, title].joined(separator: "|"),
			number: number,
			title: title,
			relationship: relationship,
			legisInfoURL: legisInfoURL
		)
	}
}

private extension KeyedDecodingContainer {
	func decodeArray<T: Decodable>(_ keys: [Key]) -> [T] {
		for key in keys {
			if let values = try? decodeIfPresent([T].self, forKey: key) {
				return values
			}
		}
		return []
	}

	func decodeStringList(_ keys: [Key]) -> [String] {
		for key in keys {
			if let values = try? decodeIfPresent([String].self, forKey: key) {
				return values.map(Self.clean).filter { !$0.isEmpty }
			}
			if let value = try? decodeIfPresent(String.self, forKey: key) {
				let cleaned = Self.clean(value)
				return cleaned.isEmpty ? [] : [cleaned]
			}
		}
		return []
	}

	private static func clean(_ value: String) -> String {
		value.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
