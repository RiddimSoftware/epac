import Foundation

enum MPLobbyingExposureDefaults {
	static let currentParliament = 45
	static let pageSize = 50
}

enum MPLobbyingWindow: String, CaseIterable, Codable, Identifiable, Sendable {
	case last30Days = "30d"
	case threeMonths = "3m"
	case twelveMonths = "12m"
	case allTime = "all"

	var id: String {
		rawValue
	}
}

struct MPLobbyingExposure: Equatable, Sendable {
	let memberID: String
	let parliament: Int
	let window: MPLobbyingWindow
	let page: Int
	let perPage: Int
	let total: Int
	let pages: Int
	let summary: MPLobbyingSummary
	let subjectBreakdown: [MPLobbyingSubjectDistribution]
	let timeline: [MPLobbyingTimelineEntry]
	let citation: String
	let sourceURL: URL

	func appendingTimeline(from nextPage: MPLobbyingExposure) -> MPLobbyingExposure {
		MPLobbyingExposure(
			memberID: nextPage.memberID,
			parliament: nextPage.parliament,
			window: nextPage.window,
			page: nextPage.page,
			perPage: nextPage.perPage,
			total: nextPage.total,
			pages: nextPage.pages,
			summary: nextPage.summary,
			subjectBreakdown: nextPage.subjectBreakdown,
			timeline: timeline + nextPage.timeline,
			citation: nextPage.citation,
			sourceURL: nextPage.sourceURL
		)
	}
}

struct MPLobbyingSummary: Equatable, Sendable {
	let memberID: String
	let parliament: Int
	let quarterStart: Date?
	let window: MPLobbyingWindow
	let totalCommunicationCount: Int
	let uniqueOrganizationsCount: Int
	let mostFrequentSubjectMatter: String?
	let topOrganizations: [MPLobbyingTopOrganization]
	let trendVsPreviousParliament: MPLobbyingTrend
	let partyAverageCommunications: Double
	let nationalAverageCommunications: Double
	let citation: String
	let updatedAt: Date?
}

struct MPLobbyingTopOrganization: Identifiable, Equatable, Sendable {
	let id: String
	let name: String
	let sector: String?
	let communicationCount: Int

	init(id: String? = nil, name: String, sector: String?, communicationCount: Int) {
		self.id = id ?? Self.slug(for: name)
		self.name = name
		self.sector = sector
		self.communicationCount = communicationCount
	}

	private static func slug(for value: String) -> String {
		MPLobbyingSubjectDistribution.slug(for: value)
	}
}

struct MPLobbyingTrend: Equatable, Sendable {
	let currentParliament: Int
	let previousParliament: Int
	let delta: Int
}

struct MPLobbyingSubjectDistribution: Identifiable, Equatable, Sendable {
	let subjectMatter: String
	let communicationCount: Int

	var id: String {
		subjectSlug
	}

	var subjectSlug: String {
		Self.slug(for: subjectMatter)
	}

	static func slug(for value: String) -> String {
		let allowed = CharacterSet.alphanumerics
		let lowercased = value.lowercased()
		let scalars = lowercased.unicodeScalars.map { scalar in
			allowed.contains(scalar) ? Character(scalar) : "-"
		}
		let rawSlug = String(scalars)
			.split(separator: "-")
			.joined(separator: "-")
		return rawSlug.isEmpty ? "unspecified" : rawSlug
	}
}

struct MPLobbyingTimelineEntry: Identifiable, Equatable, Sendable {
	let communicationID: String
	let date: Date?
	let organizationName: String
	let organizationSector: String?
	let subjectMatter: String
	let communicationType: String
	let billCrossReference: MPLobbyingBillCrossReference?
	let citation: String
	let sourceURL: URL

	var id: String {
		communicationID
	}

	var subjectSlug: String {
		MPLobbyingSubjectDistribution.slug(for: subjectMatter)
	}
}

struct MPLobbyingBillCrossReference: Equatable, Sendable {
	let billNumber: String
	let billTitle: String?
	let url: URL
	let mappingConfidence: Double
}
