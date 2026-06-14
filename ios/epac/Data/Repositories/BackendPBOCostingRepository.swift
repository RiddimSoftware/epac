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

private struct PBOCostingBackendResponse: Decodable {
    let costings: [PBOCostingDTO]

    init(from decoder: Decoder) throws {
        if let array = try? [PBOCostingDTO](from: decoder) {
            costings = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.arrayKeys {
            if let array = try container.decodeIfPresent([PBOCostingDTO].self, forKey: key) {
                costings = array
                return
            }
        }

        var collected: [PBOCostingDTO] = []
        for key in CodingKeys.singleKeys {
            if let costing = try container.decodeIfPresent(PBOCostingDTO.self, forKey: key) {
                collected.append(costing)
            }
        }

        if !collected.isEmpty {
            costings = collected
            return
        }

        costings = (try? PBOCostingDTO(from: decoder)).map { [$0] } ?? []
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case costings
        case pboCostings = "pbo_costings"
        case notes
        case publications
        case reports
        case items
        case latest
        case costing
        case pboCosting = "pbo_costing"
        case publication
        case report

        static let arrayKeys: [CodingKeys] = [
            .costings,
            .pboCostings,
            .notes,
            .publications,
            .reports,
            .items
        ]

        static let singleKeys: [CodingKeys] = [
            .latest,
            .costing,
            .pboCosting,
            .publication,
            .report
        ]
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
        id = container.firstString(for: [.id, .publicationID, .slug])
        title = container.firstString(for: [.title, .titleEn, .name])
        headlineFigureMillions = container.firstString(for: [
            .headlineFigureMillions,
            .headlineFigureMillionsSnake,
            .fiveYearCostMillions,
            .fiveYearCostMillionsCamel,
            .fiveYearCost,
            .headlineFigure,
            .pboEstimate,
            .costEstimate
        ])
        methodologyCategory = container.firstString(for: [
            .methodologyCategory,
            .methodologyCategorySnake,
            .category,
            .type
        ])
        publishedAt = container.firstString(for: [
            .publishedAt,
            .publishedAtSnake,
            .publicationDate,
            .publicationDateCamel,
            .published,
            .releaseDate,
            .releaseDateCamel
        ])
        reportURL = container.firstString(for: [
            .reportURL,
            .reportURLSnake,
            .pdfURL,
            .pdfURLSnake,
            .url,
            .reportUrlLower,
            .pdfUrlLower
        ])
        sourceURL = container.firstString(for: [
            .sourceURL,
            .sourceURLSnake,
            .sourceUrlLower,
            .publicationURL,
            .publicationURLSnake
        ])
        summaryText = container.firstString(for: [
            .summaryText,
            .summaryTextSnake,
            .summary,
            .abstract,
            .abstractEn,
            .description
        ])
    }

    var domain: PBOCosting? {
        let resolvedURLString = reportURL ?? sourceURL
        guard let resolvedURLString,
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
            sourceURL: sourceURL.flatMap(URL.init(string:)),
            summaryText: nonEmpty(summaryText)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case publicationID = "publication_id"
        case slug
        case title
        case titleEn = "title_en"
        case name
        case headlineFigureMillions
        case headlineFigureMillionsSnake = "headline_figure_millions"
        case fiveYearCostMillions = "five_year_cost_millions"
        case fiveYearCostMillionsCamel = "fiveYearCostMillions"
        case fiveYearCost = "five_year_cost"
        case headlineFigure = "headline_figure"
        case pboEstimate = "pbo_estimate"
        case costEstimate = "cost_estimate"
        case methodologyCategory
        case methodologyCategorySnake = "methodology_category"
        case category
        case type
        case publishedAt
        case publishedAtSnake = "published_at"
        case publicationDate = "publication_date"
        case publicationDateCamel = "publicationDate"
        case published
        case releaseDate = "release_date"
        case releaseDateCamel = "releaseDate"
        case reportURL
        case reportURLSnake = "report_url"
        case reportUrlLower = "reportUrl"
        case pdfURL
        case pdfURLSnake = "pdf_url"
        case pdfUrlLower = "pdfUrl"
        case url
        case sourceURL
        case sourceURLSnake = "source_url"
        case sourceUrlLower = "sourceUrl"
        case publicationURL = "publicationURL"
        case publicationURLSnake = "publication_url"
        case summaryText
        case summaryTextSnake = "summary_text"
        case summary
        case abstract
        case abstractEn = "abstract_en"
        case description
    }
}

private extension KeyedDecodingContainer where K == PBOCostingDTO.CodingKeys {
    func firstString(for keys: [K]) -> String? {
        for key in keys {
            if let stringValue = try? decodeIfPresent(String.self, forKey: key),
               let stringValue {
                return stringValue
            }
            if let intValue = try? decodeIfPresent(Int.self, forKey: key),
               let intValue {
                return String(intValue)
            }
            if let doubleValue = try? decodeIfPresent(Double.self, forKey: key),
               let doubleValue {
                return String(doubleValue)
            }
        }
        return nil
    }
}
