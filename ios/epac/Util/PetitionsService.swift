//
//  PetitionsService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches e-Petition listings from the Parliament of Canada petitions portal.
//  The portal does not expose a structured JSON API; the search endpoint returns
//  an HTML fragment. This service parses that fragment with regular expressions.
//  All data traces to petitions.ourcommons.ca — an authoritative Parliament source.
//

import Foundation

struct PetitionsService {

    private static let searchURL = URL(string: "https://petitions.ourcommons.ca/en/Petition/SearchAsync")!
    private static let basePortalURL = "https://petitions.ourcommons.ca"

    // MARK: - Public

    /// Fetches open e-Petitions for Parliament 44.
    /// Returns an empty array on any network or parse failure.
    static func fetchOpenPetitions() async throws -> [EPetition] {
        var request = URLRequest(url: searchURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // pageSize=100 to get a broad set in one call (portal supports up to 100)
        let body = "parl=44&status=Open&pageIndex=1&pageSize=100&order=Recent"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["html"] as? String else {
            return []
        }
        return parseRows(from: html)
    }

    // MARK: - HTML Parsing

    /// Parses petition rows from the HTML fragment returned by SearchAsync.
    ///
    /// The fragment contains a `<tbody id="montr">` table with `<tr class="Pub" data-id="…">` rows.
    /// Each row has: petition number, subject, keywords, open-until date, sponsor MP, signature count.
    private static func parseRows(from html: String) -> [EPetition] {
        // Match each <tr class="Pub" …> … </tr> block
        let rowPattern = #"<tr class="Pub"[^>]*data-id="\d+"[^>]*>(.*?)</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let nsHtml = html as NSString
        let rowMatches = rowRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))

        return rowMatches.compactMap { match -> EPetition? in
            let r = match.range(at: 1)
            guard r.location != NSNotFound else { return nil }
            let rowContent = nsHtml.substring(with: r)
            return parseRow(rowContent)
        }
    }

    private static func parseRow(_ content: String) -> EPetition? {
        // Petition number and subject:
        // <a … href="Details?Petition=e-7344"><span class="spTitle">e-7344 </span><span>Transportation</span></a>
        guard let idSubjectMatch = content.firstMatch(
            pattern: #"href="Details\?Petition=(e-\d+)"[^>]*><span[^>]*>(e-\d+)[^<]*</span><span>([^<]+)</span>"#
        ) else { return nil }

        let petitionID = idSubjectMatch[1]
        let subject = idSubjectMatch[3].htmlDecoded

        // Keywords: each <li><a …>Keyword</a></li> in the keywords column
        let keywordMatches = content.allMatches(pattern: #"class="index"[^>]*>([^<]+)</a>"#)
        let keywords = keywordMatches.map { $0[1].htmlDecoded }

        // Sponsor MP: last <td> text (after the open-until column)
        // The row has columns: [title, keywords, icon, open-until, sponsor, signatures]
        // We find sponsor by its position — the named <a class="publicationSponsorSearch"> if present,
        // or fallback to the 5th <td> text value.
        var sponsor = ""
        if let sponsorMatch = content.firstMatch(pattern: #"class="publicationSponsorSearch"[^>]*>([^<]+)<"#) {
            sponsor = sponsorMatch[1].htmlDecoded
        } else if let tdMatches = content.allMatchesIfAny(pattern: #"<td>([^<]{3,})</td>"#), tdMatches.count >= 1 {
            // Fallback: last plain <td> with meaningful text is usually the sponsor
            sponsor = tdMatches.last?[1].htmlDecoded ?? ""
        }

        // Signature count: last <td> with a plain integer
        var signatureCount = 0
        if let sigMatch = content.lastMatch(pattern: #"<td>(\d+)</td>"#) {
            signatureCount = Int(sigMatch[1]) ?? 0
        }

        // Deadline: "until July 23, 2026, at 11:55 a.m. (EDT)"
        var deadline: Date?
        if let deadlineMatch = content.firstMatch(
            pattern: #"until ([A-Z][a-z]+ \d{1,2}, \d{4})"#
        ) {
            deadline = parseDeadlineDate(deadlineMatch[1])
        }

        // Status is always "Open" for this query
        let status: PetitionStatus = .open

        let petitionURL = URL(string: "\(basePortalURL)/en/Petition/Details?Petition=\(petitionID)")
                        ?? URL(string: basePortalURL)!

        return EPetition(
            id: petitionID,
            subject: subject,
            keywords: keywords,
            sponsorName: sponsor,
            signatureCount: signatureCount,
            deadline: deadline,
            status: status,
            petitionURL: petitionURL
        )
    }

    // MARK: - Date Parsing

    private static let deadlineFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMMM d, yyyy"
        return df
    }()

    private static func parseDeadlineDate(_ raw: String) -> Date? {
        return deadlineFormatter.date(from: raw)
    }
}

// MARK: - String Regex Helpers (file-private)

private extension String {
    var htmlDecoded: String {
        // Minimal HTML entity decoding for the entities the portal uses
        var s = self
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns capture groups [0: full match, 1: group1, …] for the first match, or nil.
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { i -> String in
            let r = match.range(at: i)
            return r.location != NSNotFound ? (self as NSString).substring(with: r) : ""
        }
    }

    /// Returns the last match's capture groups, or nil.
    func lastMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let matches = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
        guard let match = matches.last else { return nil }
        return (0..<match.numberOfRanges).map { i -> String in
            let r = match.range(at: i)
            return r.location != NSNotFound ? (self as NSString).substring(with: r) : ""
        }
    }

    /// Returns capture groups for every match.
    func allMatches(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: self, range: NSRange(self.startIndex..., in: self)).map { match in
            (0..<match.numberOfRanges).map { i -> String in
                let r = match.range(at: i)
                return r.location != NSNotFound ? (self as NSString).substring(with: r) : ""
            }
        }
    }

    func allMatchesIfAny(pattern: String) -> [[String]]? {
        let results = allMatches(pattern: pattern)
        return results.isEmpty ? nil : results
    }
}
