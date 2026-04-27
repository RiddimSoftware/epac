//
//  OntarioLegislatureService.swift
//  epac
//
//  Fetches Ontario MPP profiles from Ontario Open Data and recent Queen's Park
//  debates from the Ontario Legislative Assembly website.
//  Results are cached in UserDefaults for one week.
//  All failures return an empty array — never crash.
//

import Foundation

struct OntarioLegislatureService {
    private static let cacheKey = "epac.ontario.mpps"
    private static let cacheTimestampKey = "epac.ontario.mpps.ts"
    private static let cacheTTL: TimeInterval = 7 * 86_400 // 1 week
    // Known-good fallback URL: literal is always valid, forced unwrap is intentional.
    // swiftlint:disable:next force_unwrapping
    private static let olaFallbackURL: URL = URL(string: "https://www.ola.org/en/members/current")!

    // MARK: - Public API

    static func fetchMPPs() async -> [OntarioMPP] {
        if let cached = loadFromCache() { return cached }

        // Try Ontario Open Data portal first (most structured)
        if let mpps = await fetchFromOpenData(), !mpps.isEmpty {
            saveToCache(mpps)
            return mpps
        }

        // Fallback: OLA website HTML
        if let mpps = await fetchFromOLA(), !mpps.isEmpty {
            saveToCache(mpps)
            return mpps
        }

        return []
    }

    static func mppsForRiding(_ riding: String, from mpps: [OntarioMPP]) -> OntarioMPP? {
        mpps.first {
            $0.riding.localizedCaseInsensitiveContains(riding) ||
            riding.localizedCaseInsensitiveContains($0.riding)
        }
    }

    static func fetchRecentDebates() async -> [OntarioDebateDay] {
        guard let url = URL(string: "https://www.ola.org/en/legislative-business/house-documents/parliament-43/session-1/hansard") else { return [] }
        guard let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return [] }

        var debates: [OntarioDebateDay] = []
        let pattern = #"href="(/en/legislative-business/house-documents/parliament-\d+/session-\d+/hansard/[^"]+)"[^>]*>[^<]*(\w+ \d+, \d{4})"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }

        let isoParser = DateFormatter()
        isoParser.dateFormat = "MMMM d, yyyy"
        isoParser.locale = Locale(identifier: "en_US_POSIX")

        let range = NSRange(html.startIndex..., in: html)
        re.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let dateRange = Range(match.range(at: 2), in: html) else { return }
            let path = String(html[pathRange])
            let dateStr = String(html[dateRange])
            let date = isoParser.date(from: dateStr)
            let urlStr = "https://www.ola.org\(path)"
            guard let url = URL(string: urlStr) else { return }
            let id = path.components(separatedBy: "/").last ?? dateStr.replacingOccurrences(of: " ", with: "-")
            debates.append(OntarioDebateDay(
                id: id,
                date: date,
                title: "Debates and Proceedings",
                parliament: 43,
                session: 1,
                publicationURL: url
            ))
        }
        return Array(debates.prefix(20))
    }

    // MARK: - Ontario Open Data (primary)

    private static func fetchFromOpenData() async -> [OntarioMPP]? {
        let urlStr = "https://data.ontario.ca/api/3/action/datastore_search?resource_id=971c45c0-9dc3-4e37-ac31-eaee7cd3ff95&limit=200"
        guard let url = URL(string: urlStr),
              let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let records = result["records"] as? [[String: Any]] else { return nil }

        return records.compactMap { record -> OntarioMPP? in
            let fn = record["first_name"] as? String
                ?? record["First Name"] as? String ?? ""
            let ln = record["last_name"] as? String
                ?? record["Last Name"] as? String ?? ""
            let riding = record["riding"] as? String
                ?? record["Riding"] as? String
                ?? record["Electoral District"] as? String ?? ""
            let party = record["party"] as? String
                ?? record["Party"] as? String ?? ""
            guard !fn.isEmpty, !ln.isEmpty, !riding.isEmpty else { return nil }
            let email = record["email"] as? String ?? record["Email"] as? String
            let profileURLStr = record["url"] as? String ?? "https://www.ola.org/en/members/current"
            let profileURL = URL(string: profileURLStr) ?? olaFallbackURL
            let id = "\(fn)-\(ln)"
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            return OntarioMPP(
                id: id,
                firstName: fn,
                lastName: ln,
                party: party,
                riding: riding,
                email: email,
                profileURL: profileURL
            )
        }
    }

    // MARK: - OLA website HTML (fallback)

    private static func fetchFromOLA() async -> [OntarioMPP]? {
        guard let url = URL(string: "https://www.ola.org/en/members/current"),
              let (data, _) = try? await NetworkService.shared.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }

        var results: [OntarioMPP] = []
        let pattern = #"class="member-name"[^>]*>\s*<[^>]*>([^<]+)</[^>]*>\s*</[^>]*>.*?class="member-constituency"[^>]*>\s*([^<]+)\s*</[^>]*>.*?class="member-party"[^>]*>\s*([^<]+)\s*</[^>]*>.*?href="(/en/members/[^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        re.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match else { return }
            func extract(_ idx: Int) -> String {
                guard let r = Range(match.range(at: idx), in: html) else { return "" }
                return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let fullName = extract(1)
            let riding = extract(2)
            let party = extract(3)
            let path = extract(4)
            guard !fullName.isEmpty else { return }
            let parts = fullName.components(separatedBy: " ")
            let fn = parts.dropLast().joined(separator: " ")
            let ln = parts.last ?? ""
            let profileURL = URL(string: "https://www.ola.org\(path)") ?? olaFallbackURL
            let id = fullName
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            results.append(OntarioMPP(
                id: id,
                firstName: fn,
                lastName: ln,
                party: party,
                riding: riding,
                email: nil,
                profileURL: profileURL
            ))
        }
        return results.isEmpty ? nil : results
    }

    // MARK: - Cache

    private static func loadFromCache() -> [OntarioMPP]? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let ts   = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date,
            Date().timeIntervalSince(ts) < cacheTTL,
            let mpps = try? JSONDecoder().decode([OntarioMPP].self, from: data)
        else { return nil }
        return mpps
    }

    private static func saveToCache(_ mpps: [OntarioMPP]) {
        guard let data = try? JSONEncoder().encode(mpps) else { return }
        UserDefaults.standard.set(data,  forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }
}
