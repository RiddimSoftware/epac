//
//  LiveParliamentService.swift
//  epac
//
//  Reads the backend-cached current House status for the Home feed live card.
//

import Foundation

struct LiveParliamentStatus: Decodable, Equatable {
    enum Status: String, Decodable {
        case sitting
        case adjourned
        case unknown
    }

    let status: Status
    let isSitting: Bool
    let businessType: String
    let currentItemTitle: String?
    let currentBillNumber: String?
    let currentSpeakerName: String?
    let divisionInProgress: Bool
    let checkedAt: Date
    let lastChangedAt: Date?
    /// YYYY-MM-DD calendar date (Ottawa-local) of the current or most-recent sitting.
    /// Preserved by the backend after `is_sitting` flips false so the Home card can
    /// transition to "TODAY IN PARLIAMENT" once Hansard publishes for that date.
    let sittingDate: String?
    let sourceURL: URL

    enum CodingKeys: String, CodingKey {
        case status
        case isSitting = "is_sitting"
        case businessType = "business_type"
        case currentItemTitle = "current_item_title"
        case currentBillNumber = "current_bill_number"
        case currentSpeakerName = "current_speaker_name"
        case divisionInProgress = "division_in_progress"
        case checkedAt = "checked_at"
        case lastChangedAt = "last_changed_at"
        case sittingDate = "sitting_date"
        case sourceURL = "source_url"
    }
}

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
