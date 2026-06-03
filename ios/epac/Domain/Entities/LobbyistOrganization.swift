import Foundation

enum LobbyistOrganizationType: String, Codable, Sendable {
	case corporation
	case nonProfit = "non_profit"
	case association
	case indigenousOrganization = "indigenous_organization"
}

enum LobbyistRegistrationStatus: String, Codable, Sendable {
	case active
	case expired
}

enum LobbyistRegistrationKind: String, Codable, Sendable {
	case consultant
	case inHouse = "in_house"
}

struct LobbyistOrganization: Identifiable, Equatable, Sendable {
	let id: String
	let oclOrganizationID: String?
	let name: String
	let type: LobbyistOrganizationType
	let sector: String?
	let registeredLobbyists: [RegisteredLobbyist]
	let activeSubjectMatters: [String]
	let communicationVolume: LobbyistOrganizationCommunicationVolume
	let topDPOHsContacted: [LobbyistOrganizationDPOHContact]
	let registrationStatus: LobbyistRegistrationStatus
	let registrations: [LobbyistRegistration]
	let recentCommunications: [LobbyistOrganizationCommunication]
	let subjectMatters: [LobbyistOrganizationSubjectMatter]
	let citation: String
	let sourceURL: URL

	var activeRegistrations: [LobbyistRegistration] {
		registrations.filter { $0.status == .active }
	}

	var expiredRegistrations: [LobbyistRegistration] {
		registrations.filter { $0.status == .expired }
	}
}

struct LobbyistOrganizationDirectory: Equatable, Sendable {
	let page: Int
	let perPage: Int
	let citation: String
	let sourceURL: URL
	let rows: [LobbyistOrganizationDirectoryRow]
}

struct LobbyistOrganizationDirectoryRow: Identifiable, Equatable, Sendable {
	let id: String
	let name: String
	let type: LobbyistOrganizationType
	let sector: String?
	let communicationVolumeCurrentParliament: Int
}

struct RegisteredLobbyist: Identifiable, Equatable, Sendable {
	let name: String
	let kind: LobbyistRegistrationKind

	var id: String {
		"\(kind.rawValue)|\(name)"
	}
}

struct LobbyistOrganizationCommunicationVolume: Equatable, Sendable {
	let currentParliament: Int
	let priorParliament: Int
}

struct LobbyistOrganizationDPOHContact: Identifiable, Equatable, Sendable {
	let memberID: String?
	let name: String
	let institution: String
	let count: Int

	var id: String {
		memberID ?? "\(name)|\(institution)"
	}
}

struct LobbyistRegistration: Identifiable, Equatable, Sendable {
	let id: String
	let status: LobbyistRegistrationStatus
	let kind: LobbyistRegistrationKind
	let subjectMatters: [String]
	let targetedInstitutions: [String]
	let sourceURL: URL
}

struct LobbyistOrganizationCommunication: Identifiable, Equatable, Sendable {
	let id: String
	let date: Date?
	let dpohMemberID: String?
	let dpohName: String
	let institution: String
	let subjectMatters: [String]
	let sourceURL: URL
}

struct LobbyistOrganizationSubjectMatter: Identifiable, Equatable, Sendable {
	let subjectMatter: String
	let communicationCount: Int
	let topicSlug: String?

	var id: String {
		subjectMatter
	}
}
