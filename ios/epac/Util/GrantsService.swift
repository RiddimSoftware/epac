import Foundation

// Fetches federal grants and contributions from Treasury Board Secretariat
// Proactive Disclosure via the open.canada.ca CKAN Datastore API.
// Source: open.canada.ca — Government of Canada Open Data Portal.
// No AI-generated content.

struct GrantsService {
    private enum Constants {
        static let defaultFetchLimit = 200
        static let ridingFetchLimit = 100
        static let requestTimeout: TimeInterval = 30
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    // CKAN Datastore resource ID for TBS Proactive Disclosure – Grants and Contributions.
    // Stable resource identifier published by Treasury Board Secretariat.
    // Dataset: https://open.canada.ca/data/en/dataset/432527ab-7aac-45b5-81d6-7597107a7013
    private static let resourceID = "1d15a62f-5656-49ad-8c88-f40ce689d831"
    private static let apiBase = URL(string: "https://open.canada.ca/data/api/action/datastore_search")!
    // April is the first month of the Canadian federal fiscal year.
    private static let fiscalYearStartMonth = 4

    // MARK: - Public

    static func fetchGrants(
        limit: Int = Constants.defaultFetchLimit,
        query: String? = nil,
        department: String? = nil,
        recipientType: String? = nil,
        province: String? = nil,
        fiscalYear: String? = nil
    ) async throws -> [GrantContribution] {
        let url = try buildURL(
            limit: limit,
            query: query,
            department: department,
            recipientType: recipientType,
            province: province,
            fiscalYear: fiscalYear
        )
        return try await fetch(url: url)
    }

    static func fetchGrantsForProvince(_ province: String, limit: Int = Constants.ridingFetchLimit) async throws -> [GrantContribution] {
        let url = try buildURL(limit: limit, province: province, fiscalYear: currentFiscalYear())
        return try await fetch(url: url)
    }

    // MARK: - Private

    static func currentFiscalYear() -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: Date())
        // Canadian fiscal year runs April 1 – March 31.
        return month >= fiscalYearStartMonth ? "\(year)-\(year + 1)" : "\(year - 1)-\(year)"
    }

    private static func buildURL(
        limit: Int,
        query: String? = nil,
        department: String? = nil,
        recipientType: String? = nil,
        province: String? = nil,
        fiscalYear: String? = nil
    ) throws -> URL {
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "resource_id", value: resourceID),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "agreement_value desc NULLS LAST")
        ]
        if let q = query, !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        let filters = buildFilters(department: department, recipientType: recipientType, province: province, fiscalYear: fiscalYear)
        if !filters.isEmpty {
            let filterJSON = try JSONSerialization.data(withJSONObject: filters)
            items.append(URLQueryItem(name: "filters", value: String(data: filterJSON, encoding: .utf8)))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private static func buildFilters(
        department: String?,
        recipientType: String?,
        province: String?,
        fiscalYear: String?
    ) -> [String: String] {
        var filters: [String: String] = [:]
        if let dept = department, !dept.isEmpty { filters["owner_org_title"] = dept }
        if let rt = recipientType, !rt.isEmpty { filters["recipient_type_en"] = rt }
        if let prov = province, !prov.isEmpty { filters["recipient_province_en"] = prov }
        if let fy = fiscalYear, !fy.isEmpty { filters["fiscal_year"] = fy }
        return filters
    }

    private static func fetch(url: URL) async throws -> [GrantContribution] {
        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              Constants.successStatusCodes.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parseGrants(from: data)
    }

    private static func parseGrants(from data: Data) throws -> [GrantContribution] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any],
              let records = result["records"] as? [[String: Any]] else {
            return []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return records.compactMap { record -> GrantContribution? in
            let id = record["ref_number"] as? String ?? UUID().uuidString
            let recipient = (record["recipient_name_en"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !recipient.isEmpty else { return nil }

            let valueStr = record["agreement_value"] as? String ?? "0"
            let amount = Double(valueStr) ?? 0
            guard amount > 0 else { return nil }

            let dept = (record["owner_org_title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let purpose = ((record["proj_name_en"] as? String) ?? (record["prog_name_en"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let city = (record["recipient_city_en"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let province = (record["recipient_province_en"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let location = [city, province].filter { !$0.isEmpty }.joined(separator: ", ")
            let recipientType = (record["recipient_type_en"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let fiscalYear = record["fiscal_year"] as? String ?? ""
            let dateStr = record["expected_date"] as? String ?? record["agreement_start_date"] as? String ?? ""
            let date = formatter.date(from: dateStr) ?? .now

            return GrantContribution(
                id: id,
                recipientName: recipient,
                amount: amount,
                department: dept,
                purpose: purpose,
                recipientLocation: location,
                recipientProvince: province,
                recipientType: recipientType,
                fiscalYear: fiscalYear,
                agreementDate: date
            )
        }
    }
}
