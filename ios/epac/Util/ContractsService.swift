import Foundation

// Fetches federal government contracts from Treasury Board Secretariat
// Proactive Disclosure via the open.canada.ca CKAN Datastore API.
// Source: open.canada.ca — Government of Canada Open Data Portal.
// No AI-generated content.

struct ContractsService {
    private enum Constants {
        static let defaultFetchLimit = 100
        static let requestTimeout: TimeInterval = 30
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    // CKAN datastore resource ID for "Proactive Disclosure - Contracts" (all departments).
    // This ID is stable and published by Treasury Board Secretariat.
    // https://open.canada.ca/data/en/dataset/d8f85d91-7dec-4fd1-8055-483b77225d8b
    private static let resourceID = "fac950c0-00d5-4ec1-a4d3-9cbebf98a305"
    private static let apiBase   = URL(string: "https://open.canada.ca/data/api/action/datastore_search")!

    // MARK: - Public

    /// Fetches the most recent high-value contracts, sorted descending by contract value.
    static func fetchTopContracts(limit: Int = Constants.defaultFetchLimit, query: String? = nil, department: String? = nil) async throws -> [GovernmentContract] {
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "resource_id", value: resourceID),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "contract_value desc NULLS LAST")
        ]
        if let q = query, !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        if let dept = department, !dept.isEmpty {
            items.append(URLQueryItem(name: "q", value: "owner_org_title:\(dept)"))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parseContracts(from: data)
    }

    // MARK: - Private

    private static func parseContracts(from data: Data) throws -> [GovernmentContract] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any],
              let records = result["records"] as? [[String: Any]] else {
            return []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return records.compactMap { record -> GovernmentContract? in
            let id         = record["reference_number"] as? String ?? UUID().uuidString
            let dept       = (record["owner_org_title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let vendor     = (record["vendor_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let purpose    = ((record["description_en"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let amendments = record["amendment_count"] as? Int ?? 0

            let valueStr  = record["contract_value"] as? String ?? "0"
            let origStr   = record["original_value"] as? String ?? valueStr
            let value     = Double(valueStr) ?? 0
            let orig      = Double(origStr) ?? value

            guard !vendor.isEmpty, value > 0 else { return nil }

            let dateStr  = record["contract_date"] as? String ?? ""
            let date     = formatter.date(from: dateStr) ?? .now
            let fiscal   = record["fiscal_year"] as? String ?? ""

            return GovernmentContract(
                id: id,
                department: dept,
                vendor: vendor,
                value: value,
                purpose: purpose,
                contractDate: date,
                amendmentCount: amendments,
                originalValue: orig,
                fiscalYear: fiscal
            )
        }
    }
}
