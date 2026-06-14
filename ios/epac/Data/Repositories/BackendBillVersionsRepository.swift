import Foundation

/// Loads a bill's published-versions list from the epac backend.
///
/// Contract — `GET /api/v1/bills/{id}` (bill-depth endpoint):
/// - `200`: bill JSON whose `versions` field carries the list (see
///   `BillDepthVersionsResponse`). The backend has already ingested LEGISinfo
///   published versions into the bill artifact, so the iOS side only decodes
///   and renders.
/// - `204` / `404`: backend has no record for that bill; the "Compare
///   versions" entry point hides.
///
/// The iOS layer never parses LEGISinfo or parl.ca wire formats; this typed
/// JSON shape is the boundary between backend and app.
struct BackendBillVersionsRepository: BillVersionsRepository {
    fileprivate enum Constants {
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let noContentStatus = 204
        static let notFoundStatus = 404
        static let pathPrefix = "api/v1/bills"

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

    func loadBillVersions(billID: String) async throws -> [BillVersion]? {
        let path = "\(Constants.pathPrefix)/\(billID)"
        guard let data = try await get(path: path) else {
            return nil
        }
        let response = try decoder.decode(BillDepthVersionsResponse.self, from: data)
        return response.bill.versions.map(\.domain)
    }

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

private struct BillDepthVersionsResponse: Decodable {
    let bill: BillDTO
}

private struct BillDTO: Decodable {
    let versions: [VersionDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versions = try container.decodeIfPresent([VersionDTO].self, forKey: .versions) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case versions
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
            publishedOn: BackendBillVersionsRepository.parseDate(publishedOn),
            sourceURL: sourceURL
        )
    }
}
