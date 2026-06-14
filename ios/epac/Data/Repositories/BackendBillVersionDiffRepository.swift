import Foundation

/// Loads a clause-level diff between two published bill versions from the
/// epac backend.
///
/// Contract — `GET /api/v1/bills/{id}/diff?from={fromVersionID}&to={toVersionID}`:
/// - `200`: diff JSON (see `BillVersionDiffResponse`). The backend has already
///   run the clause-aware diff against the published version text, so the iOS
///   side only decodes and renders.
/// - `204` / `404`: backend cannot produce a diff for the requested pair (one
///   of the versions is missing text, or the diff job has not run for that
///   pair yet); the diff viewer renders an unavailable state.
///
/// The iOS layer never parses LEGISinfo or parl.ca wire formats; this typed
/// JSON shape is the boundary between backend and app, and the clause-aware
/// diff algorithm lives in the backend.
struct BackendBillVersionDiffRepository: BillVersionDiffRepository {
    fileprivate enum Constants {
        static let requestTimeout: TimeInterval = 25
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let noContentStatus = 204
        static let notFoundStatus = 404
        static let pathPrefix = "api/v1/bills"
        static let pathSuffix = "diff"
        static let fromQueryItem = "from"
        static let toQueryItem = "to"

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

    func loadBillVersionDiff(
        billID: String,
        fromVersionID: String,
        toVersionID: String
    ) async throws -> BillVersionDiff? {
        guard let url = makeURL(
            billID: billID,
            fromVersionID: fromVersionID,
            toVersionID: toVersionID
        ) else {
            return nil
        }
        guard let data = try await get(url: url) else {
            return nil
        }
        return try decoder.decode(BillVersionDiffResponse.self, from: data).domain
    }

    private func makeURL(
        billID: String,
        fromVersionID: String,
        toVersionID: String
    ) -> URL? {
        let basePath = baseURL.appending(path: "\(Constants.pathPrefix)/\(billID)/\(Constants.pathSuffix)")
        guard var components = URLComponents(url: basePath, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: Constants.fromQueryItem, value: fromVersionID),
            URLQueryItem(name: Constants.toQueryItem, value: toVersionID)
        ]
        return components.url
    }

    private func get(url: URL) async throws -> Data? {
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

private struct BillVersionDiffResponse: Decodable {
    let from: VersionDTO
    let to: VersionDTO
    let clauses: [ClauseDiffDTO]

    enum CodingKeys: String, CodingKey {
        case from
        case to
        case clauses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(VersionDTO.self, forKey: .from)
        to = try container.decode(VersionDTO.self, forKey: .to)
        clauses = try container.decodeIfPresent([ClauseDiffDTO].self, forKey: .clauses) ?? []
    }

    var domain: BillVersionDiff {
        BillVersionDiff(
            fromVersion: from.domain,
            toVersion: to.domain,
            clauseDiffs: clauses.map(\.domain)
        )
    }
}

private struct VersionDTO: Decodable {
    let id: String?
    let label: String?
    let title: String?
    let stage: String?
    let chamber: String?
    let publishedOn: String?
    let sourceURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case title
        case stage
        case chamber
        case publishedOn = "published_on"
        case sourceURL = "source_url"
    }

    var domain: BillVersion {
        BillVersion(
            id: id ?? label ?? UUID().uuidString,
            label: label ?? "",
            title: title?.isEmpty == false ? title : nil,
            stage: stage?.isEmpty == false ? stage : nil,
            chamber: chamber?.isEmpty == false ? chamber : nil,
            publishedOn: BackendBillVersionDiffRepository.parseDate(publishedOn),
            sourceURL: sourceURL
        )
    }
}

private struct ClauseDiffDTO: Decodable {
    let id: String?
    let label: String?
    let changeType: String?
    let fromText: String?
    let toText: String?
    let hansardAnchorURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case changeType = "change_type"
        case fromText = "from_text"
        case toText = "to_text"
        case hansardAnchorURL = "hansard_anchor_url"
    }

    var domain: BillClauseDiff {
        let resolvedLabel = label ?? ""
        let resolvedID = id ?? (resolvedLabel.isEmpty ? UUID().uuidString : resolvedLabel)
        return BillClauseDiff(
            id: resolvedID,
            label: resolvedLabel,
            changeType: BillClauseChangeType.from(changeType ?? ""),
            fromText: fromText ?? "",
            toText: toText ?? "",
            hansardAnchorURL: hansardAnchorURL
        )
    }
}
