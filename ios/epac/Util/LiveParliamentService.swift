//
//  LiveParliamentService.swift
//  epac
//
//  Reads the backend-cached current House status for the Home feed live card.
//

import Foundation

// LiveParliamentStatus struct lives in Domain/Entities/LiveParliamentStatus.swift

struct LiveParliamentService: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let dataLoader: DataLoader

    init(
        baseURL: URL = BackendConfig.shared.baseURL,
        dataLoader: @escaping DataLoader = { request in
            try await NetworkService.shared.data(for: request)
        }
    ) {
        self.baseURL = baseURL
        self.dataLoader = dataLoader
    }

    func fetchStatus() async throws -> LiveParliamentStatus {
        #if DEBUG
        if let fixture = Self.debugFixtureJSON(),
           let data = fixture.data(using: .utf8) {
            return try Self.decoder.decode(LiveParliamentStatus.self, from: data)
        }
        #endif

        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("live")
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(LiveParliamentStatus.self, from: data)
    }

    #if DEBUG
    private static func debugFixtureJSON() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--live-status-fixture-json"),
           arguments.indices.contains(arguments.index(after: index)) {
            return arguments[arguments.index(after: index)]
        }
        return ProcessInfo.processInfo.environment["EPAC_DEBUG_LIVE_STATUS_FIXTURE_JSON"]
    }
    #endif

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601Date(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }()

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }

        let wholeSecond = ISO8601DateFormatter()
        wholeSecond.formatOptions = [.withInternetDateTime]
        return wholeSecond.date(from: raw)
    }
}
