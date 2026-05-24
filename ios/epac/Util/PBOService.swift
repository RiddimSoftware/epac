//
//  PBOService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches PBO Legislative Costing Notes from the PBO public REST API at
//  https://rest-393962616e6b.pbo-dpb.ca/ and matches them to a given bill number.
//
//  API discovery notes (2026-04-27):
//  - The PBO website (pbo-dpb.ca) is a Vue SPA; direct HTML scraping yields nothing useful.
//  - The SPA's axios base is https://rest-393962616e6b.pbo-dpb.ca/ (from data-apiroot attr).
//  - Two endpoints are useful:
//      GET /publications?types=LEG    — paginated list of Legislative Costing Notes
//      GET /search?query=<term>&types=Publication — free-text search across all publications
//  - Each publication object has a `bills` array with `bill_num` (e.g. "C-265"),
//    `parliament`, `session`, and `permalinks.en.website`.
//  - There are no cost-figure fields in the API; the estimate lives in the PDF.
//    The abstract (`metadata.abstract_en`) describes what was costed.
//

import Foundation

struct PBOService {

    // The PBO website is a Vue SPA; the REST base URL lives in the page's `data-apiroot` attribute.
    // The subdomain hex "393962616e6b" decodes to "99bank" — a stable internal label, not a version
    // number. If this URL ever returns 404, reload pbo-dpb.ca and grep the page source for
    // `data-apiroot` to find the current base.
    private static let restBase = URL(string: "https://rest-393962616e6b.pbo-dpb.ca/")!

    /// Parse an ISO 8601 date string. Created fresh per call to avoid Sendable issues with
    /// ISO8601DateFormatter under Swift 6 strict concurrency.
    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        // Fallback without fractional seconds
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    // MARK: - Public interface

    /// Fetch PBO Legislative Costing Notes that reference the given bill number.
    /// Returns an empty array (never throws) when the bill has no PBO coverage or the network fails.
    static func fetchReports(matching billNumber: String) async -> [PBOReport] {
        guard !billNumber.isEmpty else { return [] }

        // Primary strategy: search full-text for the bill number, then exact-match the bills array.
        if let reports = await fetchViaSearch(billNumber: billNumber), !reports.isEmpty {
            return reports
        }

        // Secondary strategy: scan recent LEG publications page by page.
        return await fetchViaLEGListing(billNumber: billNumber)
    }

    // MARK: - Strategy 1: search endpoint

    private static func fetchViaSearch(billNumber: String) async -> [PBOReport]? {
        guard let url = searchURL(for: billNumber),
              let data = await fetchData(from: url),
              let payloads = searchPayloads(from: data) else { return nil }

        return sortedReports(from: payloads, matching: billNumber)
    }

    // MARK: - Strategy 2: LEG publications listing

    private static func fetchViaLEGListing(billNumber: String) async -> [PBOReport] {
        var results: [PBOReport] = []

        // Scan up to 5 pages of recent LEG notes (15 per page = 75 publications — sufficient for current session)
        for page in 1...5 {
            guard let items = await legListingItems(page: page) else { break }

            if items.isEmpty { break }

            results.append(contentsOf: sortedReports(from: items, matching: billNumber))
        }
        return results.sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }
    }

    private static func searchURL(for billNumber: String) -> URL? {
        guard var components = URLComponents(
            url: restBase.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: billNumber),
            URLQueryItem(name: "types", value: "Publication")
        ]
        return components.url
    }

    private static func legListingItems(page: Int) async -> [[String: Any]]? {
        guard var components = URLComponents(
            url: restBase.appendingPathComponent("publications"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "types", value: "LEG"),
            URLQueryItem(name: "sort", value: "latest"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        guard let url = components.url,
              let data = await fetchData(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        return root["data"] as? [[String: Any]]
    }

    private static func fetchData(from url: URL) async -> Data? {
        guard let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }

        return data
    }

    private static func searchPayloads(from data: Data) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return root.values.compactMap { value in
            guard let entry = value as? [String: Any] else { return nil }
            return entry["payload"] as? [String: Any]
        }
    }

    private static func sortedReports(from items: [[String: Any]], matching billNumber: String) -> [PBOReport] {
        items
            .compactMap { extractReport(from: $0, matching: billNumber) }
            .sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }
    }

    // MARK: - Extraction

    /// Returns a PBOReport if `item` references `billNumber` in its bills array or title.
    private static func extractReport(from item: [String: Any], matching billNumber: String) -> PBOReport? {
        // Match via the structured bills array (preferred — exact bill_num match)
        let bills = item["bills"] as? [[String: Any]] ?? []
        let billMatch = bills.contains { bill in
            guard let billNum = bill["bill_num"] as? String else { return false }
            return billNum.caseInsensitiveCompare(billNumber) == .orderedSame
        }

        // Fallback: title contains the bill number as a word boundary match
        let titleEn = item["title_en"] as? String ?? ""
        let titleFr = item["title_fr"] as? String ?? ""
        let titleMatch = containsBillNumber(billNumber, in: titleEn) || containsBillNumber(billNumber, in: titleFr)

        guard billMatch || titleMatch else { return nil }

        // Only include LEG type (Legislative Costing Notes) and RP (Reports with bill estimates)
        let type = item["type"] as? String ?? ""
        guard type == "LEG" || type == "RP" else { return nil }

        // Extract fields
        let id = item["id"] as? String ?? item["internal_id"] as? String ?? UUID().uuidString
        let title = titleEn.isEmpty ? (item["title_fr"] as? String ?? "") : titleEn

        let abstract = (item["metadata"] as? [String: Any])?["abstract_en"] as? String ?? ""

        let dateStr = item["release_date"] as? String ?? item["is_published"] as? String ?? ""
        let reportDate = parseDate(dateStr)

        // Report URL from permalinks
        let permalinks = item["permalinks"] as? [String: Any]
        let enPermalink = (permalinks?["en"] as? [String: Any])?["website"] as? String
        guard let urlStr = enPermalink, let reportURL = URL(string: urlStr) else { return nil }

        return PBOReport(
            id: id,
            title: title,
            billReference: billNumber,
            pboEstimate: nil,       // Cost figures live in the PDF, not the API
            governmentEstimate: nil,
            reportDate: reportDate,
            reportURL: reportURL,
            summary: abstract
        )
    }

    /// True if `text` contains `billNumber` as a standalone token (e.g. "Bill C-50" or "C-50:").
    private static func containsBillNumber(_ billNumber: String, in text: String) -> Bool {
        guard !billNumber.isEmpty, !text.isEmpty else { return false }
        // Require the bill number to appear as a complete token, not as a substring of a longer number
        let pattern = "(?i)(?:^|[^0-9A-Za-z-])" + NSRegularExpression.escapedPattern(for: billNumber) + "(?:$|[^0-9A-Za-z-])"
        return (try? NSRegularExpression(pattern: pattern))?.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) != nil
    }
}
