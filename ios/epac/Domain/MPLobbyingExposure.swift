import Foundation

struct MPLobbyingExposureResponse: Codable, Sendable {
    static let empty = MPLobbyingExposureResponse(
        memberID: "",
        page: 0,
        perPage: 0,
        total: 0,
        pages: 0,
        summary: .empty,
        timeline: [],
        subjectDistribution: [],
        topOrganizations: [],
        cohortComparison: .empty,
        availableSubjects: []
    )

    let memberID: String
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
    let summary: MPLobbyingSummary
    let timeline: [MPLobbyingTimelineEntry]
    let subjectDistribution: [MPLobbyingSubjectDistribution]
    let topOrganizations: [MPLobbyingTopOrganization]
    let cohortComparison: MPLobbyingCohortComparison
    let availableSubjects: [String]

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case page
        case perPage = "per_page"
        case total
        case pages
        case summary
        case timeline
        case subjectDistribution = "subject_distribution"
        case topOrganizations = "top_organizations"
        case cohortComparison = "cohort_comparison"
        case availableSubjects = "available_subjects"
    }
}

struct MPLobbyingSummary: Codable, Sendable {
    let totalCommunications: Int
    let uniqueOrganizations: Int
    let mostFrequentSubject: String
    let previousParliamentCommunications: Int
    let trendVsPreviousParliament: Double

    static let empty = MPLobbyingSummary(
        totalCommunications: 0,
        uniqueOrganizations: 0,
        mostFrequentSubject: "",
        previousParliamentCommunications: 0,
        trendVsPreviousParliament: 0
    )

    enum CodingKeys: String, CodingKey {
        case totalCommunications = "total_communications"
        case uniqueOrganizations = "unique_organizations"
        case mostFrequentSubject = "most_frequent_subject"
        case previousParliamentCommunications = "previous_parliament_communications"
        case trendVsPreviousParliament = "trend_vs_previous_parliament"
    }
}

struct MPLobbyingTimelineEntry: Codable, Sendable, Identifiable, Hashable {
    let communicationDate: String?
    let organizationName: String
    let organizationSector: String
    let subjectMatter: String
    let communicationType: String
    let organizationID: String
    let organizationProfileURL: String
    let relatedBillTitle: String
    let relatedBillURL: String
    let relatedBillConfidence: Double
    let relatedBillConfidenceUsed: Bool
    let recordURL: String

    enum CodingKeys: String, CodingKey {
        case communicationDate = "communication_date"
        case organizationName = "organization_name"
        case organizationSector = "organization_sector"
        case subjectMatter = "subject_matter"
        case communicationType = "communication_type"
        case organizationID = "organization_id"
        case organizationProfileURL = "organization_profile_url"
        case relatedBillTitle = "related_bill_title"
        case relatedBillURL = "related_bill_url"
        case relatedBillConfidence = "related_bill_confidence"
        case relatedBillConfidenceUsed = "related_bill_confidence_used"
        case recordURL = "record_url"
    }

    var id: String {
        [communicationDate ?? "", organizationName, organizationSector, subjectMatter, communicationType, organizationID, recordURL]
            .joined(separator: "|")
    }

    var communicationDateValue: Date? {
        guard let dateString = communicationDate else { return nil }
        return Self.dateFormatter.date(from: dateString)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct MPLobbyingSubjectDistribution: Codable, Sendable, Identifiable, Hashable {
    let subject: String
    let count: Int
    let percentage: Double

    enum CodingKeys: String, CodingKey {
        case subject
        case count
        case percentage
    }

    var id: String { subject }
}

struct MPLobbyingTopOrganization: Codable, Sendable, Identifiable, Hashable {
    let organizationName: String
    let organizationSector: String
    let count: Int
    let organizationID: String
    let organizationProfileURL: String

    enum CodingKeys: String, CodingKey {
        case organizationName = "organization_name"
        case organizationSector = "organization_sector"
        case count
        case organizationID = "organization_id"
        case organizationProfileURL = "organization_profile_url"
    }

    var id: String { [organizationName, organizationSector, organizationID].joined(separator: "|") }
}

struct MPLobbyingCohortComparison: Codable, Sendable {
    let party: String
    let partyAverage: Double
    let nationalAverage: Double
    let partyRatio: Double
    let nationalRatio: Double

    enum CodingKeys: String, CodingKey {
        case party
        case partyAverage = "party_average"
        case nationalAverage = "national_average"
        case partyRatio = "party_ratio"
        case nationalRatio = "national_ratio"
    }

    static let empty = MPLobbyingCohortComparison(
        party: "",
        partyAverage: 0,
        nationalAverage: 0,
        partyRatio: 0,
        nationalRatio: 0
    )
}
