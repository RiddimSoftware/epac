//
//  SenatorsService.swift
//  epac
//
//  Created on 2026-04-27.
//
//  Fetches senator profiles from the OurCommons open API with an XML fallback.
//  Results are cached in UserDefaults for one week.
//  All failures return an empty array — never crash.
//

import Foundation

struct SenatorsService {
    private static let cacheKey      = "epac.senators.cache"
    private static let cacheTimestampKey = "epac.senators.cache.ts"
    private enum Constants {
        static let cacheDays: TimeInterval = 7
        static let secondsPerDay: TimeInterval = 86_400
        static let successStatusLowerBound = 200
        static let successStatusUpperBound = 300
        static let provinceAbbreviationLength = 2

        static var cacheTTL: TimeInterval {
            cacheDays * secondsPerDay
        }

        static var successStatusCodes: Range<Int> {
            successStatusLowerBound..<successStatusUpperBound
        }
    }

    // MARK: - Public API

    static func fetchSenators() async -> [Senator] {
        if let cached = loadFromCache() { return cached }

        if let senators = await fetchFromOpenAPI(), !senators.isEmpty {
            saveToCache(senators)
            return senators
        }

        if let senators = await fetchFromXML(), !senators.isEmpty {
            saveToCache(senators)
            return senators
        }

        return []
    }

    static func senators(for province: String, from senators: [Senator]) -> [Senator] {
        senators
            .filter { $0.province.uppercased() == province.uppercased() }
            .sorted { $0.lastName < $1.lastName }
    }

    // MARK: - OurCommons open API (primary)

    private static func fetchFromOpenAPI() async -> [Senator]? {
        guard let url = URL(string:
            "https://api.openparliament.ca/ocd/members/?parliament=45&chamber=Senate&pageSize=200&format=json"
        ) else { return nil }

        guard let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              Constants.successStatusCodes.contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return nil }

        return items.compactMap { item -> Senator? in
            guard let fn = item["PersonOfficialFirstName"] as? String,
                  let ln = item["PersonOfficialLastName"] as? String else { return nil }
            let provinceFull = item["ProvinceName"] as? String
                ?? item["ProvinceNameEn"] as? String
                ?? ""
            let abbrev = provinceAbbrev(provinceFull)
            guard !abbrev.isEmpty else { return nil }

            let caucus     = item["CaucusAbbreviationEn"] as? String
                ?? item["CaucusShortName"] as? String
                ?? ""
            let caucusFull = item["CaucusNameEn"] as? String ?? caucus

            let id = "\(fn)-\(ln)-\(abbrev)"
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")

            let urlStr = item["PersonPageUrl"] as? String
                ?? "https://sencanada.ca/en/senators/"
            let senateURL = URL(string: urlStr)
                ?? URL(string: "https://sencanada.ca/en/senators/")!

            var date: Date?
            if let dateStr = item["StartDate"] as? String {
                date = ISO8601DateFormatter().date(from: dateStr)
            }

            return Senator(
                id: id,
                firstName: fn,
                lastName: ln,
                province: abbrev,
                caucus: caucus,
                caucusFullName: caucusFull,
                senateURL: senateURL,
                appointedDate: date
            )
        }
    }

    // MARK: - OurCommons XML (fallback)

    private static func fetchFromXML() async -> [Senator]? {
        guard let url = URL(string:
            "https://www.ourcommons.ca/Members/en/search/XML?parliament=all&caucusId=all&province=all&gender=all"
        ) else { return nil }

        guard let (data, _) = try? await NetworkService.shared.data(from: url),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        var results: [Senator] = []

        let blockRegex = try? NSRegularExpression(
            pattern: "<MemberOfParliament>.*?</MemberOfParliament>",
            options: .dotMatchesLineSeparators
        )
        let range = NSRange(xml.startIndex..., in: xml)
        blockRegex?.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: xml) else { return }
            let block = String(xml[r])
            guard let senator = senator(fromXMLBlock: block) else { return }
            results.append(senator)
        }

        return results.isEmpty ? nil : results
    }

    private static func senator(fromXMLBlock block: String) -> Senator? {
        guard block.lowercased().contains("senator") else { return nil }

        let fn = extractXMLValue("PersonOfficialFirstName", from: block)
        let ln = extractXMLValue("PersonOfficialLastName", from: block)
        let province = extractXMLValue("ConstituencyProvinceTerritoryName", from: block)
        let caucus = extractXMLValue("CaucusShortName", from: block)

        guard !fn.isEmpty, !ln.isEmpty, !province.isEmpty else { return nil }
        let abbrev = provinceAbbrev(province)
        guard !abbrev.isEmpty else { return nil }

        let id = "\(fn)-\(ln)-\(abbrev)"
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let senateURL = URL(string: "https://sencanada.ca/en/senators/")!

        return Senator(
            id: id,
            firstName: fn,
            lastName: ln,
            province: abbrev,
            caucus: caucus,
            caucusFullName: caucus,
            senateURL: senateURL,
            appointedDate: nil
        )
    }

    private static func extractXMLValue(_ tag: String, from block: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "<\(tag)>(.*?)</\(tag)>"),
              let match = re.firstMatch(
                  in: block,
                  range: NSRange(block.startIndex..., in: block)
              ),
              let range = Range(match.range(at: 1), in: block) else { return "" }

        return String(block[range])
    }

    // MARK: - Province mapping

    private static func provinceAbbrev(_ full: String) -> String {
        let map: [String: String] = [
            "British Columbia": "BC",
            "Alberta": "AB",
            "Saskatchewan": "SK",
            "Manitoba": "MB",
            "Ontario": "ON",
            "Quebec": "QC",
            "Québec": "QC",
            "New Brunswick": "NB",
            "Nova Scotia": "NS",
            "Prince Edward Island": "PE",
            "Newfoundland and Labrador": "NL",
            "Northwest Territories": "NT",
            "Nunavut": "NU",
            "Yukon": "YT"
        ]
        return map[full] ?? (full.count == Constants.provinceAbbreviationLength ? full.uppercased() : "")
    }

    // MARK: - Cache

    private static func loadFromCache() -> [Senator]? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let ts   = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date,
            Date().timeIntervalSince(ts) < Constants.cacheTTL,
            let senators = try? JSONDecoder().decode([Senator].self, from: data)
        else { return nil }
        return senators
    }

    private static func saveToCache(_ senators: [Senator]) {
        guard let data = try? JSONEncoder().encode(senators) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }
}
