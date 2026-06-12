//
//  BackendPetitionGovernmentResponseQueryPort.swift
//  epac
//

import Foundation

@MainActor
struct BackendPetitionGovernmentResponseQueryPort: PetitionGovernmentResponseQueryPort {
    fileprivate enum Constants {
        static let requestTimeout: TimeInterval = 20
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let notFoundStatusCode = 404
        static let pathPrefix = "api/v1/petitions"
        static let pathSuffix = "response"

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

    func fetchGovernmentResponse(for petitionID: String) async throws -> PetitionGovernmentResponse? {
        let path = "\(Constants.pathPrefix)/\(petitionID)/\(Constants.pathSuffix)"
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == Constants.notFoundStatusCode {
            return nil
        }

        guard Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let dto = try decoder.decode(PetitionGovernmentResponseDTO.self, from: data)
        return dto.domain
    }
}

private struct PetitionGovernmentResponseDTO: Decodable {
    let text: String
    let tabledOn: String
    let respondingMinister: String?

    enum CodingKeys: String, CodingKey {
        case text
        case tabledOn = "tabled_on"
        case respondingMinister = "responding_minister"
    }

    var domain: PetitionGovernmentResponse {
        let date = Self.parseDate(tabledOn) ?? Date()
        return PetitionGovernmentResponse(
            text: text,
            tabledOn: date,
            respondingMinister: respondingMinister
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
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
