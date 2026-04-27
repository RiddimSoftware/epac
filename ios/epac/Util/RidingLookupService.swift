import Foundation

struct RidingLookupResult {
    let memberName: String
    let ridingName: String
    let partyName: String
}

enum RidingLookupError: LocalizedError, Equatable {
    case invalidPostalCode
    case networkError
    case noFederalRepresentative
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidPostalCode:
            return NSLocalizedString("riding.error.invalidPostalCode", comment: "")
        case .networkError:
            return NSLocalizedString("riding.error.networkError", comment: "")
        case .noFederalRepresentative:
            return NSLocalizedString("riding.error.noFederalRepresentative", comment: "")
        case .noResults:
            return NSLocalizedString("riding.error.noResults", comment: "")
        }
    }
}

struct RidingLookupService {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw RidingLookupError.networkError
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RidingLookupError.noResults
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boundaries = json["boundaries_centroid"] as? [[String: Any]] else {
            throw RidingLookupError.noResults
        }

        // Find the current federal electoral district (exclude 2003 representation-order boundaries).
        let federalBoundary = boundaries.first {
            let setName = ($0["boundary_set_name"] as? String) ?? ""
            let relatedURL = (($0["related"] as? [String: Any])?["boundary_set_url"] as? String) ?? ""
            return setName == "Federal electoral district"
                && !relatedURL.contains("2003-representation-order")
        }

        guard let ridingName = federalBoundary?["name"] as? String, !ridingName.isEmpty else {
            throw RidingLookupError.noFederalRepresentative
        }

        return ridingName
    }

    /// Normalize for fuzzy match: lowercase, collapse em/en-dashes to hyphens, strip diacritics.
    static func normalizeRidingName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .folding(options: .diacriticInsensitive, locale: nil)
    }

    private func isValidCanadianPostalCode(_ code: String) -> Bool {
        code.range(of: "^[A-Z]\\d[A-Z]\\d[A-Z]\\d$", options: .regularExpression) != nil
    }
}
