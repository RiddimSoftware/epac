import Foundation

/// Loads the amendments tabled against a bill from the epac backend.
///
/// Contract — `GET /api/v1/bills/{id}`:
/// - `200`: bill depth JSON. We decode only the `bill.amendments` array and
///   ignore the rest of the bill payload. The backend aligns LEGISinfo
///   amendment records with committee minutes from parl.ca, so the iOS side
///   only decodes and renders.
/// - `204` / `404`: the bill is not known to the backend index, so the panel
///   shows the empty state (no amendments).
///
/// The iOS layer never parses LEGISinfo or parl.ca wire formats directly; this
/// typed JSON shape is the boundary between backend and app.
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

    func loadBillAmendments(billID: String) async throws -> [BillAmendment] {
        let path = "\(Constants.pathPrefix)/\(billID)"
        guard let data = try await get(path: path) else {
            return []
        }
        let response = try decoder.decode(BillAmendmentsBillDepthResponse.self, from: data)
        return response.bill.amendments.map(\.domain)
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

private struct BillAmendmentsBillDepthResponse: Decodable {
    let bill: BillEnvelope
}

private struct BillEnvelope: Decodable {
    let amendments: [AmendmentDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amendments = try container.decodeIfPresent([AmendmentDTO].self, forKey: .amendments) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case amendments
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        number = try container.decodeIfPresent(String.self, forKey: .number)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
        sponsorName = try container.decodeIfPresent(String.self, forKey: .sponsorName)
        proposedOn = try container.decodeIfPresent(String.self, forKey: .proposedOn)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
    }

    var domain: BillAmendment {
        let rawStatus = status ?? ""
        return BillAmendment(
            id: id ?? number ?? UUID().uuidString,
            number: number ?? "",
            clauseReference: title ?? "",
            status: BillAmendmentStatus(backendValue: rawStatus),
            rawStatus: rawStatus,
            stage: stage ?? "",
            moverName: sponsorName ?? "",
            proposedOn: BackendBillAmendmentsRepository.parseDate(proposedOn),
            text: text ?? "",
            sourceURL: sourceURL
        )
    }
}
