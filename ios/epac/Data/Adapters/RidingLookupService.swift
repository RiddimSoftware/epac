import Foundation

struct RidingLookupService: Sendable {
    private enum Constants {
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    private let baseURL = URL(string: "https://represent.opennorth.ca")!

    /// Returns the current federal riding name for a given postal code.
    /// The caller is responsible for resolving the MP from local data.
    func lookupRiding(postalCode: String) async throws -> String {
        let normalized = postalCode.uppercased().filter { !$0.isWhitespace }
        guard isValidCanadianPostalCode(normalized) else {
            throw RidingLookupError.invalidPostalCode
        }

        guard let url = URL(string: "postcodes/\(normalized)/", relativeTo: baseURL)?
            .appending(queryItems: [URLQueryItem(name: "sets", value: "federal-electoral-districts")]) else {
            throw RidingLookupError.invalidPostalCode
        }

        let data = try await fetchLookupData(from: url)
        return try ridingName(from: data)
    }

    /// Normalize for fuzzy match: lowercase, collapse em/en-dashes to hyphens, strip diacritics.
    static func normalizeRidingName(_ name: String) -> String {
        RidingNameNormalizer.normalize(name)
    }

    private func isValidCanadianPostalCode(_ code: String) -> Bool {
        code.range(of: "^[A-Z]\\d[A-Z]\\d[A-Z]\\d$", options: .regularExpression) != nil
    }

    private func fetchLookupData(from url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await NetworkService.shared.data(from: url)
        } catch {
            throw RidingLookupError.networkError
        }

        if let http = response as? HTTPURLResponse, !Constants.successStatusCodes.contains(http.statusCode) {
            throw RidingLookupError.noResults
        }

        return data
    }

    private func ridingName(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boundaries = json["boundaries_centroid"] as? [[String: Any]] else {
            throw RidingLookupError.noResults
        }

        guard let ridingName = currentFederalBoundary(from: boundaries)?["name"] as? String,
              !ridingName.isEmpty else {
            throw RidingLookupError.noFederalRepresentative
        }

        return ridingName
    }

    private func currentFederalBoundary(from boundaries: [[String: Any]]) -> [String: Any]? {
        boundaries.first {
            let setName = ($0["boundary_set_name"] as? String) ?? ""
            let relatedURL = (($0["related"] as? [String: Any])?["boundary_set_url"] as? String) ?? ""
            return setName == "Federal electoral district"
                && !relatedURL.contains("2003-representation-order")
        }
    }
}
