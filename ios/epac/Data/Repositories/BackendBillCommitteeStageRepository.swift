import Foundation

/// Loads a bill's committee study stage from the epac backend.
///
/// Contract - `GET /api/v1/bills/{id}/committee-stage`:
/// - `200`: committee-stage JSON (see `BillCommitteeStageResponse`). The backend
///   has already aligned the LEGISinfo "in committee" status with the parl.ca
///   committee schedule, so the iOS side only decodes and renders.
/// - `204` / `404`: the bill is not currently before a committee, so the panel
///   is hidden.
///
/// The iOS layer never parses LEGISinfo or parl.ca wire formats directly; this
/// typed JSON shape is the boundary between backend and app.
struct BackendBillCommitteeStageRepository: BillCommitteeStageRepository {
    fileprivate enum Constants {
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let noContentStatus = 204
        static let notFoundStatus = 404
        static let pathPrefix = "api/v1/bills"
        static let pathSuffix = "committee-stage"

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

    func loadBillCommitteeStage(billID: String) async throws -> BillCommitteeStage? {
        let path = "\(Constants.pathPrefix)/\(billID)/\(Constants.pathSuffix)"
        guard let data = try await get(path: path) else {
            return nil
        }
        return try decoder.decode(BillCommitteeStageResponse.self, from: data).domain
    }

    /// Returns the response bytes for a 2xx, or `nil` for `204`/`404`.
    /// Throws for any other status.
    private func get(path: String) async throws -> Data? {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == Constants.noContentStatus || http.statusCode == Constants.notFoundStatus {
            return nil
        }
        guard Constants.successStatusCodes.contains(http.statusCode) else {
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

// MARK: - Backend JSON contract

private struct BillCommitteeStageResponse: Decodable {
    let committee: CommitteeDTO
    let studiedSince: String?
    let studyCompletedAt: String?
    let upcomingMeetings: [MeetingDTO]
    let pastMeetings: [MeetingDTO]

    enum CodingKeys: String, CodingKey {
        case committee
        case studiedSince = "studied_since"
        case studyCompletedAt = "study_completed_at"
        case upcomingMeetings = "upcoming_meetings"
        case pastMeetings = "past_meetings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        committee = try container.decode(CommitteeDTO.self, forKey: .committee)
        studiedSince = try container.decodeIfPresent(String.self, forKey: .studiedSince)
        studyCompletedAt = try container.decodeIfPresent(String.self, forKey: .studyCompletedAt)
        upcomingMeetings = try container.decodeIfPresent([MeetingDTO].self, forKey: .upcomingMeetings) ?? []
        pastMeetings = try container.decodeIfPresent([MeetingDTO].self, forKey: .pastMeetings) ?? []
    }

    var domain: BillCommitteeStage {
        BillCommitteeStage(
            committee: committee.domain,
            studiedSince: BackendBillCommitteeStageRepository.parseDate(studiedSince),
            studyCompletedAt: BackendBillCommitteeStageRepository.parseDate(studyCompletedAt),
            upcomingMeetings: upcomingMeetings.map(\.domain),
            pastMeetings: pastMeetings.map(\.domain)
        )
    }
}

private struct CommitteeDTO: Decodable {
    let code: String
    let name: String
    let chamber: String?
    let url: URL

    var domain: ParliamentaryCommittee {
        ParliamentaryCommittee(
            id: code,
            acronym: code,
            name: name,
            chamberCode: chamber ?? "HOC",
            committeeURL: url
        )
    }
}

private struct MeetingDTO: Decodable {
    let id: String
    let meetingNumber: Int
    let date: String?
    let witnessCount: Int?
    let evidenceURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case meetingNumber = "meeting_number"
        case date
        case witnessCount = "witness_count"
        case evidenceURL = "evidence_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        meetingNumber = try container.decode(Int.self, forKey: .meetingNumber)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        witnessCount = try container.decodeIfPresent(Int.self, forKey: .witnessCount)
        evidenceURL = try container.decodeIfPresent(URL.self, forKey: .evidenceURL)
    }

    var domain: BillCommitteeMeeting {
        BillCommitteeMeeting(
            id: id,
            meetingNumber: meetingNumber,
            date: BackendBillCommitteeStageRepository.parseDate(date),
            witnessCount: witnessCount,
            evidenceURL: evidenceURL
        )
    }
}
