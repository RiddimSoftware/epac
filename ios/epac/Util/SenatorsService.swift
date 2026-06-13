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
import UserNotifications

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

        let previousSenators = loadFromCacheBypassingTTL() ?? []

        var freshSenators: [Senator] = []
        if let senators = await fetchFromOpenAPI(), !senators.isEmpty {
            freshSenators = senators
        } else if let senators = await fetchFromXML(), !senators.isEmpty {
            freshSenators = senators
        }

        if !freshSenators.isEmpty {
            saveToCache(freshSenators)
            if await TopicFollowStore.shared.isFollowing("senate") && !previousSenators.isEmpty {
                notifyNewAppointments(fresh: freshSenators, previous: previousSenators)
            }
            return freshSenators
        }

        return previousSenators.isEmpty ? [] : previousSenators
    }

    static func senators(for province: String, from senators: [Senator]) -> [Senator] {
        senators
            .filter { $0.province.uppercased() == province.uppercased() }
            .sorted { $0.lastName < $1.lastName }
    }

    // MARK: - OurCommons open API (primary)

    private static func fetchFromOpenAPI() async -> [Senator]? {
        let url = BackendConfig.shared.baseURL.appendingPathComponent("api/v1/senators")

        guard let (data, response) = try? await NetworkService.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              Constants.successStatusCodes.contains(http.statusCode) else { return nil }

        return parseOpenAPISenators(from: data)
    }

    static func parseOpenAPISenators(from data: Data) -> [Senator]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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

            let appointmentPayload = item["appointment"] as? [String: Any] ?? item
            let appointmentDateValue = stringValue(
                forAnyKey: ["appointment_date", "appointmentDate", "appointed_date", "appointedDate", "date", "StartDate"],
                in: appointmentPayload
            ) ?? stringValue(
                forAnyKey: ["appointment_date", "appointmentDate", "appointed_date", "appointedDate", "StartDate"],
                in: item
            )
            let date = parseDate(appointmentDateValue)
            let primeMinisterKeys = [
                "appointing_prime_minister",
                "appointingPrimeMinister",
                "appointing_pm",
                "appointingPM",
                "appointed_by",
                "appointedBy",
                "prime_minister",
                "primeMinister",
                "prime_minister_name",
                "primeMinisterName",
                "PrimeMinisterName"
            ]
            let appointingPrimeMinister = stringValue(forAnyKey: primeMinisterKeys, in: appointmentPayload)
                ?? stringValue(forAnyKey: primeMinisterKeys, in: item)
            let sourceURLKeys = [
                "source_url",
                "sourceURL",
                "sourceUrl",
                "orders_in_council_url",
                "ordersInCouncilURL",
                "ordersInCouncilUrl",
                "order_in_council_url",
                "orderInCouncilURL",
                "orderInCouncilUrl",
                "OrderInCouncilURL"
            ]
            let sourceURL = urlValue(forAnyKey: sourceURLKeys, in: appointmentPayload)
                ?? urlValue(forAnyKey: sourceURLKeys, in: item)
                ?? SenateAppointment.defaultSourceURL
            let affiliationKeys = [
                "declared_affiliation",
                "declaredAffiliation",
                "affiliation",
                "caucus_full_name",
                "caucusFullName",
                "CaucusNameEn"
            ]
            let declaredAffiliation = stringValue(forAnyKey: affiliationKeys, in: appointmentPayload)
                ?? stringValue(forAnyKey: affiliationKeys, in: item)
                ?? caucusFull
            let appointment = date.map {
                SenateAppointment(
                    date: $0,
                    appointingPrimeMinister: appointingPrimeMinister,
                    province: abbrev,
                    declaredAffiliation: declaredAffiliation,
                    sourceURL: sourceURL
                )
            }

            return Senator(
                id: id,
                firstName: fn,
                lastName: ln,
                province: abbrev,
                caucus: caucus,
                caucusFullName: caucusFull,
                senateURL: senateURL,
                appointedDate: date,
                appointment: appointment
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
            appointedDate: nil,
            appointment: nil
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

    private static func stringValue(forAnyKey keys: [String], in item: [String: Any]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func urlValue(forAnyKey keys: [String], in item: [String: Any]) -> URL? {
        guard let rawValue = stringValue(forAnyKey: keys, in: item) else { return nil }
        return URL(string: rawValue)
    }

    private static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        if let date = ISO8601DateFormatter().date(from: rawValue) {
            return date
        }
        return dateOnlyFormatter.date(from: rawValue)
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

    private static func loadFromCacheBypassingTTL() -> [Senator]? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let senators = try? JSONDecoder().decode([Senator].self, from: data)
        else { return nil }
        return senators
    }

    private static func notifyNewAppointments(fresh: [Senator], previous: [Senator]) {
        let previousIDs = Set(previous.map { $0.id })
        let newAppointments = fresh.filter { !previousIDs.contains($0.id) }
        for senator in newAppointments {
            triggerNotification(for: senator)
        }
    }

    private static func triggerNotification(for senator: Senator) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("senate.notification.title", comment: "")
        let bodyFormat = NSLocalizedString("senate.notification.body", comment: "")
        let pm = senator.appointment?.appointingPrimeMinister ?? ""
        content.body = String(format: bodyFormat, senator.name, senator.province, pm)
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(
            identifier: "epac.senator-appointment.\(senator.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.error("Failed to post senator appointment notification: \(error)")
            } else {
                Log.debug("Posted senator appointment notification for \(senator.name)")
            }
        }
    }
}
