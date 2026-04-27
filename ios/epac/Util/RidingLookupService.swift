import Foundation

struct RidingLookupResult {
    let memberName: String
    let ridingName: String
    let partyName: String
}

enum RidingLookupError: LocalizedError {
    case invalidPostalCode
    case networkError(Error)
    case noFederalRepresentative
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidPostalCode:
            return NSLocalizedString("riding.error.invalidPostalCode", comment: "")
        case .networkError(let error):
            return error.localizedDescription
        case .noFederalRepresentative:
            return NSLocalizedString("riding.error.noFederalRepresentative", comment: "")
        case .noResults:
            return NSLocalizedString("riding.error.noResults", comment: "")
        }
    }
}

struct RidingLookupService {
    private let baseURL = URL(string: "https://represent.opennorth.ca")!

    func lookup(postalCode: String) async throws -> RidingLookupResult {
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
            throw RidingLookupError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RidingLookupError.noResults
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let representatives = json["representatives_centroid"] as? [[String: Any]] else {
            throw RidingLookupError.noResults
        }

        guard let mp = representatives.first(where: { ($0["elected_office"] as? String) == "MP" }),
              let name = mp["name"] as? String, !name.isEmpty,
              let riding = mp["district_name"] as? String, !riding.isEmpty else {
            throw RidingLookupError.noFederalRepresentative
        }

        let party = mp["party_name"] as? String ?? ""
        return RidingLookupResult(memberName: name, ridingName: riding, partyName: party)
    }

    private func isValidCanadianPostalCode(_ code: String) -> Bool {
        code.range(of: "^[A-Z]\\d[A-Z]\\d[A-Z]\\d$", options: .regularExpression) != nil
    }
}
