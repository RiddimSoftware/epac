import Foundation

protocol HansardSearchProviding: Sendable {
    func search(
        query: String,
        speaker: String?,
        topic: String?,
        page: Int,
        perPage: Int
    ) async throws -> HansardSearchResponse
}

struct BackendHansardSearchService: HansardSearchProviding, Sendable {
    private enum Constants {
        static let endpointPath = "api/v1/hansard/search"
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    private let network: NetworkService
    private let baseURL: URL

    init(
        network: NetworkService = .shared,
        baseURL: URL = BackendConfig.shared.baseURL
    ) {
        self.network = network
        self.baseURL = baseURL
    }

    func search(
        query: String,
        speaker: String?,
        topic: String?,
        page: Int,
        perPage: Int
    ) async throws -> HansardSearchResponse {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            query: query,
            speaker: speaker,
            topic: topic,
            page: page,
            perPage: perPage
        )
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse,
              Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try Self.makeDecoder().decode(HansardSearchResponse.self, from: data)
    }

    static func makeRequest(
        baseURL: URL,
        query: String,
        speaker: String?,
        topic: String?,
        page: Int,
        perPage: Int
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: Constants.endpointPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let speaker {
            queryItems.append(URLQueryItem(name: "speaker", value: speaker))
        }
        if let topic {
            queryItems.append(URLQueryItem(name: "topic", value: topic))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(makeDateFormatter())
        return decoder
    }

    static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

struct HansardSearchResponse: Codable, Sendable {
    let page: Int
    let perPage: Int
    let total: Int
    let results: [HansardSearchResult]

    enum CodingKeys: String, CodingKey {
        case page, total, results
        case perPage = "per_page"
    }
}

struct HansardSearchResult: Codable, Identifiable, Sendable, Hashable {
    let parliamentNumber: Int
    let sessionNumber: Int
    let sittingDate: Date
    let interventionID: String
    let messageID: String
    let speakerName: String
    let partyAbbreviation: String
    let ridingName: String
    let topic: String
    let snippet: String
    let score: Double

    var id: String { messageID }

    enum CodingKeys: String, CodingKey {
        case parliamentNumber = "parliament_number"
        case sessionNumber = "session_number"
        case sittingDate = "sitting_date"
        case interventionID = "intervention_id"
        case messageID = "message_id"
        case speakerName = "speaker_name"
        case partyAbbreviation = "party_abbreviation"
        case ridingName = "riding_name"
        case topic, snippet, score
    }
}
