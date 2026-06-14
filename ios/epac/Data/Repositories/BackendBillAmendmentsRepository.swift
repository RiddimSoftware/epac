import Foundation

/// Loads a bill's amendments list from the epac backend.
///
/// Contract — `GET /api/v1/bills/{id}` (bill-depth endpoint):
/// - `200`: bill JSON whose `amendments` field carries the list (see
///   `BillDepthAmendmentsResponse`). The backend has already ingested
///   LEGISinfo and committee-minute amendments into the bill artifact, so the
///   iOS side only decodes and renders.
/// - `204` / `404`: backend has no record for that bill; the panel is hidden.
///
/// The iOS layer never parses LEGISinfo or parl.ca wire formats; this typed
/// JSON shape is the boundary between backend and app.
struct BackendBillAmendmentsRepository: BillAmendmentsRepository {
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

    func loadBillAmendments(billID: String) async throws -> [BillAmendment]? {
        let path = "\(Constants.pathPrefix)/\(billID)"
        guard let data = try await get(path: path) else {
            return nil
        }
        let response = try decoder.decode(BillDepthAmendmentsResponse.self, from: data)
        return response.bill.amendments.map(\.domain)
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

private struct BillDepthAmendmentsResponse: Decodable {
    let bill: BillDTO

    struct BillDTO: Decodable {
        let amendments: [AmendmentDTO]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amendments = try container.decodeIfPresent([AmendmentDTO].self, forKey: .amendments) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case amendments
        }
    }
}

private struct AmendmentDTO: Decodable {
    let id: String?
    let number: String?
    let title: String?
    let status: String?
    let stage: String?
    let sponsorName: String?
    let proposedOn: String?
    let text: String?
    let sourceURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case status
        case stage
        case sponsorName = "sponsor_name"
        case proposedOn = "proposed_on"
        case text
        case sourceURL = "source_url"
    }

    var domain: BillAmendment {
        let rawStatus = status ?? ""
        return BillAmendment(
            id: id ?? number ?? UUID().uuidString,
            number: number ?? "",
            title: title?.isEmpty == false ? title : nil,
            sponsorName: sponsorName ?? "",
            proposedOn: BackendBillAmendmentsRepository.parseDate(proposedOn),
            stage: stage ?? "",
            status: BillAmendmentStatus.from(rawStatus),
            statusLabel: rawStatus,
            text: text ?? "",
            sourceURL: sourceURL
        )
    }
}
