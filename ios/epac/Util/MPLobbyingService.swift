import Foundation

protocol MPLobbyingServiceProviding: Sendable {
    func fetchExposure(
        memberID: Int,
        page: Int,
        range: MPLobbyingDateRange,
        subject: String?
    ) async throws -> MPLobbyingExposureResponse
}

struct BackendMPLobbyingService: MPLobbyingServiceProviding, Sendable {
    private enum Constants {
        static let endpointTemplate = "api/v1/members/%d/lobbying"
        static let perPage = 50
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

    func fetchExposure(
        memberID: Int,
        page: Int = 1,
        range: MPLobbyingDateRange,
        subject: String?
    ) async throws -> MPLobbyingExposureResponse {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            memberID: memberID,
            page: page,
            range: range,
            subject: subject
        )
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse,
              Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = makeDecoder()
        return try decoder.decode(MPLobbyingExposureResponse.self, from: data)
    }

    static func makeRequest(
        baseURL: URL,
        memberID: Int,
        page: Int,
        range: MPLobbyingDateRange,
        subject: String?
    ) throws -> URLRequest {
        guard memberID > 0 else {
            throw URLError(.badURL)
        }

        guard var components = URLComponents(
            url: baseURL.appending(path: String(format: Constants.endpointTemplate, memberID)),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(Constants.perPage)),
            URLQueryItem(name: "range", value: range.apiValue)
        ]

        let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSubject.isEmpty {
            queryItems.append(URLQueryItem(name: "subject", value: trimmedSubject))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}

enum MPLobbyingDateRange: String, CaseIterable, Sendable {
    case all
    case days30 = "30d"
    case months3 = "3m"
    case months12 = "12m"

    var apiValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .all: return NSLocalizedString("lobbying.range.all", comment: "")
        case .days30: return NSLocalizedString("lobbying.range.30", comment: "")
        case .months3: return NSLocalizedString("lobbying.range.3m", comment: "")
        case .months12: return NSLocalizedString("lobbying.range.12", comment: "")
        }
    }

    static let defaultRange: MPLobbyingDateRange = .all
}
