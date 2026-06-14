import Foundation

/// Loads bill-linked PBO costing notes from the epac backend.
///
/// Contract - `GET /pbo/by-bill/{legisinfo_id}`:
/// - `200`: JSON containing one or more PBO notes linked to the bill.
/// - `204` / `404`: no linked PBO costing; the bill page hides the panel.
///
/// The backend is the boundary for PBO publication indexing and bill linking.
/// iOS decodes typed JSON only and does not scrape PBO pages.
struct BackendPBOCostingRepository: PBOCostingQueryPort {
    fileprivate enum Constants {
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let noContentStatus = 204
        static let notFoundStatus = 404
        static let pathPrefix = "pbo/by-bill"

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

    func loadPBOCostings(billID: String) async throws -> [PBOCosting]? {
        guard let data = try await get(billID: billID) else {
            return nil
        }

        let response = try decoder.decode(PBOCostingBackendResponse.self, from: data)
        return response.costings.compactMap(\.domain)
    }

    private func get(billID: String) async throws -> Data? {
        let url = baseURL
            .appending(path: Constants.pathPrefix)
            .appending(path: billID)
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

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }

        return dateOnlyFormatter.date(from: value)
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Backend JSON contract

/// Wire shape for `GET /pbo/by-bill/{legisinfo_id}`.
///
/// The documented response wraps the notes in a `costings` array. A bare
/// top-level array is also accepted so a backend that returns the list directly
/// still renders.
private struct PBOCostingBackendResponse: Decodable {
    let costings: [PBOCostingDTO]

    init(from decoder: Decoder) throws {
        if let array = try? [PBOCostingDTO](from: decoder) {
            costings = array
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        costings = try container.decodeIfPresent([PBOCostingDTO].self, forKey: .costings) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case costings
    }
}

private struct PBOCostingDTO: Decodable {
    let id: String?
    let title: String?
    let headlineFigureMillions: String?
    let methodologyCategory: String?
    let publishedAt: String?
    let reportURL: String?
    let sourceURL: String?
    let summaryText: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(forKey: .id)
        title = container.flexibleString(forKey: .title)
        headlineFigureMillions = container.flexibleString(forKey: .headlineFigureMillions)
        methodologyCategory = container.flexibleString(forKey: .methodologyCategory)
        publishedAt = container.flexibleString(forKey: .publishedAt)
        reportURL = container.flexibleString(forKey: .reportURL)
        sourceURL = container.flexibleString(forKey: .sourceURL)
        summaryText = container.flexibleString(forKey: .summaryText)
    }

    /// Maps the wire row to the domain entity, or `nil` when there is no usable
    /// report link. A note with only `source_url` falls back to that link.
    var domain: PBOCosting? {
        guard let resolvedURLString = nonEmpty(reportURL) ?? nonEmpty(sourceURL),
              let resolvedURL = URL(string: resolvedURLString) else {
            return nil
        }

        let resolvedID = nonEmpty(id) ?? resolvedURL.absoluteString
        return PBOCosting(
            id: resolvedID,
            title: nonEmpty(title) ?? resolvedID,
            headlineFigureMillions: nonEmpty(headlineFigureMillions),
            methodologyCategory: nonEmpty(methodologyCategory) ?? "other",
            publishedAt: BackendPBOCostingRepository.parseDate(publishedAt),
            reportURL: resolvedURL,
            sourceURL: nonEmpty(sourceURL).flatMap(URL.init(string:)),
            summaryText: nonEmpty(summaryText)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case headlineFigureMillions = "headline_figure_millions"
        case methodologyCategory = "methodology_category"
        case publishedAt = "published_at"
        case reportURL = "report_url"
        case sourceURL = "source_url"
        case summaryText = "summary_text"
    }
}

private extension KeyedDecodingContainer {
    /// Decodes a field the backend may send as a JSON string or number,
    /// normalising both to a string and treating an absent/null value as `nil`.
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}
